Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-LocalPortInUse {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    return $null -ne ($listeners | Where-Object { $_.Port -eq $Port } | Select-Object -First 1)
}

function Test-TcpConnection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMilliseconds
    )

    $tcpClient = [System.Net.Sockets.TcpClient]::new()
    try {
        $connectTask = $tcpClient.ConnectAsync($HostName, $Port)
        if (-not $connectTask.Wait($TimeoutMilliseconds)) {
            return $false
        }

        return $tcpClient.Connected
    }
    catch {
        return $false
    }
    finally {
        $tcpClient.Dispose()
    }
}

function Write-RecentBrokerLogs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComposeEnvPath,

        [Parameter(Mandatory = $true)]
        [string]$ComposeProjectName,

        [Parameter(Mandatory = $true)]
        [string]$ComposePath
    )

    Write-Host "Recent integration Broker logs:"
    & docker compose `
        --env-file $ComposeEnvPath `
        --project-name $ComposeProjectName `
        -f $ComposePath `
        logs --no-color --tail 100 mosquitto
}

$integrationHost = "127.0.0.1"
$integrationPort = 18883
$integrationUsername = "integration-client"
$mosquittoImage = "eclipse-mosquitto:2"
$integrationEnvironmentNames = @(
    "MQTT_INTEGRATION_CONFIG_DIR",
    "MQTT_INTEGRATION_HOST",
    "MQTT_INTEGRATION_PORT",
    "MQTT_INTEGRATION_USERNAME",
    "MQTT_INTEGRATION_PASSWORD"
)

$projectRoot = $null
$pythonPath = $null
$composePath = $null
$mosquittoFixturePath = $null
$aclFixturePath = $null
$integrationTestPath = $null
$tempRoot = $null
$tempWorkDirectory = $null
$configDirectory = $null
$composeEnvPath = $null
$integrationPassword = $null
$locationPushed = $false
$composeInvoked = $false
$cleanupFailed = $false
$finalExitCode = 1

$runId = [Guid]::NewGuid().ToString("N")
$composeProjectName = "mqtt-auth-integration-$($runId.Substring(0, 12))"

try {
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    $pythonPath = Join-Path $projectRoot ".venv\Scripts\python.exe"
    $composePath = Join-Path $projectRoot "integration_tests\compose.yaml"
    $mosquittoFixturePath = Join-Path $projectRoot "integration_tests\fixtures\mosquitto.conf"
    $aclFixturePath = Join-Path $projectRoot "integration_tests\fixtures\acl"
    $integrationTestPath = Join-Path $projectRoot "integration_tests\test_auth_acl.py"

    if (-not (Get-Command docker -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "Docker command was not found."
    }

    & docker compose version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose is not available."
    }

    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker daemon is not available."
    }

    $requiredFiles = @(
        $pythonPath,
        $composePath,
        $mosquittoFixturePath,
        $aclFixturePath,
        $integrationTestPath
    )
    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Required integration-test file was not found: $requiredFile"
        }
    }

    if (Test-LocalPortInUse -Port $integrationPort) {
        throw "Integration port $integrationHost`:$integrationPort is already in use; refusing to connect to or reuse an unknown service."
    }

    if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        throw "The system TEMP directory is not configured."
    }

    $tempRoot = (Resolve-Path -LiteralPath $env:TEMP).Path
    $tempWorkDirectory = Join-Path $tempRoot "mqtt-auth-integration-$runId"
    $configDirectory = Join-Path $tempWorkDirectory "config"
    $composeEnvPath = Join-Path $tempWorkDirectory "compose.env"

    New-Item -ItemType Directory -Path $configDirectory -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $mosquittoFixturePath -Destination $configDirectory -ErrorAction Stop
    Copy-Item -LiteralPath $aclFixturePath -Destination $configDirectory -ErrorAction Stop

    $randomBytes = New-Object byte[] 32
    $randomNumberGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $randomNumberGenerator.GetBytes($randomBytes)
    }
    finally {
        $randomNumberGenerator.Dispose()
    }
    $integrationPassword = [BitConverter]::ToString($randomBytes).Replace("-", "").ToLowerInvariant()

    $mountSpecification = "type=bind,source=$configDirectory,target=/mosquitto/config"
    Write-Host "Creating temporary Mosquitto credentials..."
    & docker run --rm `
        --mount $mountSpecification `
        $mosquittoImage `
        mosquitto_passwd -b -c /mosquitto/config/passwords `
        $integrationUsername $integrationPassword *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the temporary Mosquitto password file."
    }

    & docker run --rm `
        --mount $mountSpecification `
        --entrypoint sh `
        $mosquittoImage `
        -c "chown 1883:1883 /mosquitto/config/passwords && chmod 600 /mosquitto/config/passwords" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set safe permissions on the temporary Mosquitto password file."
    }

    $passwordFilePath = Join-Path $configDirectory "passwords"
    if (
        -not (Test-Path -LiteralPath $passwordFilePath -PathType Leaf) -or
        (Get-Item -LiteralPath $passwordFilePath).Length -le 0
    ) {
        throw "The temporary Mosquitto password file is missing or empty."
    }

    $composeConfigPath = $configDirectory.Replace("\", "/")
    $composeEnvironmentLines = @(
        "MQTT_INTEGRATION_CONFIG_DIR=$composeConfigPath",
        "MQTT_INTEGRATION_PORT=$integrationPort"
    )
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines(
        $composeEnvPath,
        $composeEnvironmentLines,
        $utf8WithoutBom
    )

    [Environment]::SetEnvironmentVariable(
        "MQTT_INTEGRATION_CONFIG_DIR",
        $configDirectory,
        "Process"
    )
    [Environment]::SetEnvironmentVariable(
        "MQTT_INTEGRATION_PORT",
        $integrationPort.ToString(),
        "Process"
    )

    Push-Location $projectRoot
    $locationPushed = $true

    Write-Host "Starting isolated integration Broker..."
    $composeInvoked = $true
    & docker compose `
        --env-file $composeEnvPath `
        --project-name $composeProjectName `
        -f $composePath `
        up -d mosquitto
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start the integration Broker."
    }

    $brokerReady = $false
    $readinessBudget = [TimeSpan]::FromSeconds(10)
    $readinessStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($readinessStopwatch.Elapsed -lt $readinessBudget) {
        $runningContainerId = & docker compose `
            --env-file $composeEnvPath `
            --project-name $composeProjectName `
            -f $composePath `
            ps --status running --quiet mosquitto 2>$null
        $composePsExitCode = $LASTEXITCODE

        if (
            $composePsExitCode -ne 0 -or
            [string]::IsNullOrWhiteSpace(($runningContainerId -join ""))
        ) {
            Write-RecentBrokerLogs `
                -ComposeEnvPath $composeEnvPath `
                -ComposeProjectName $composeProjectName `
                -ComposePath $composePath
            throw "Integration Broker exited before becoming ready."
        }

        $remainingMilliseconds = [int][Math]::Floor(
            ($readinessBudget - $readinessStopwatch.Elapsed).TotalMilliseconds
        )
        if ($remainingMilliseconds -le 0) {
            break
        }

        $tcpTimeoutMilliseconds = [Math]::Min(250, $remainingMilliseconds)
        if (
            Test-TcpConnection `
                -HostName $integrationHost `
                -Port $integrationPort `
                -TimeoutMilliseconds $tcpTimeoutMilliseconds
        ) {
            $brokerReady = $true
            break
        }

        $remainingMilliseconds = [int][Math]::Floor(
            ($readinessBudget - $readinessStopwatch.Elapsed).TotalMilliseconds
        )
        if ($remainingMilliseconds -gt 0) {
            Start-Sleep -Milliseconds ([Math]::Min(250, $remainingMilliseconds))
        }
    }
    $readinessStopwatch.Stop()

    if (-not $brokerReady) {
        Write-RecentBrokerLogs `
            -ComposeEnvPath $composeEnvPath `
            -ComposeProjectName $composeProjectName `
            -ComposePath $composePath
        throw "Integration Broker did not become ready within 10 seconds."
    }

    [Environment]::SetEnvironmentVariable(
        "MQTT_INTEGRATION_HOST",
        $integrationHost,
        "Process"
    )
    [Environment]::SetEnvironmentVariable(
        "MQTT_INTEGRATION_USERNAME",
        $integrationUsername,
        "Process"
    )
    [Environment]::SetEnvironmentVariable(
        "MQTT_INTEGRATION_PASSWORD",
        $integrationPassword,
        "Process"
    )

    Write-Host "Running MQTT authentication and ACL integration tests..."
    & $pythonPath -m pytest -q integration_tests/test_auth_acl.py -p no:cacheprovider
    $finalExitCode = $LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine("Integration test runner failed: {0}", $_.Exception.Message)
    $finalExitCode = 1
}
finally {
    foreach ($environmentName in $integrationEnvironmentNames) {
        [Environment]::SetEnvironmentVariable($environmentName, $null, "Process")
    }
    $integrationPassword = $null

    if ($composeInvoked) {
        try {
            & docker compose `
                --env-file $composeEnvPath `
                --project-name $composeProjectName `
                -f $composePath `
                down --volumes --remove-orphans
            if ($LASTEXITCODE -ne 0) {
                throw "Docker Compose teardown returned a non-zero exit code."
            }
        }
        catch {
            [Console]::Error.WriteLine("Integration Broker teardown failed: {0}", $_.Exception.Message)
            $cleanupFailed = $true
        }
    }

    if ($null -ne $tempWorkDirectory -and (Test-Path -LiteralPath $tempWorkDirectory)) {
        try {
            $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
            $resolvedWorkDirectory = [System.IO.Path]::GetFullPath($tempWorkDirectory)
            $trimCharacters = [char[]]"\/"
            $tempRootPrefix = $resolvedTempRoot.TrimEnd($trimCharacters) + [System.IO.Path]::DirectorySeparatorChar

            if (-not $resolvedWorkDirectory.StartsWith(
                $tempRootPrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
                throw "Refusing to delete a directory outside the system TEMP directory."
            }

            Remove-Item -LiteralPath $resolvedWorkDirectory -Recurse -Force -ErrorAction Stop
        }
        catch {
            [Console]::Error.WriteLine("Temporary integration directory cleanup failed: {0}", $_.Exception.Message)
            $cleanupFailed = $true
        }
    }

    if ($locationPushed) {
        try {
            Pop-Location
        }
        catch {
            [Console]::Error.WriteLine("Failed to restore the caller working directory: {0}", $_.Exception.Message)
            $cleanupFailed = $true
        }
    }

    if ($cleanupFailed -and $finalExitCode -eq 0) {
        $finalExitCode = 1
    }
}

exit $finalExitCode
