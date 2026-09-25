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

function Test-TlsConnection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonPath,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [Parameter(Mandatory = $true)]
        [string]$CaFilePath,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMilliseconds
    )

    $probeScript = @'
import socket
import ssl
import sys

host = sys.argv[1]
port = int(sys.argv[2])
ca_file = sys.argv[3]
timeout = int(sys.argv[4]) / 1000

context = ssl.create_default_context(cafile=ca_file)
with socket.create_connection((host, port), timeout=timeout) as tcp_socket:
    with context.wrap_socket(tcp_socket, server_hostname=host):
        pass
'@

    & $PythonPath `
        -c $probeScript `
        $HostName `
        $Port `
        $CaFilePath `
        $TimeoutMilliseconds *> $null
    return $LASTEXITCODE -eq 0
}

function Invoke-OpenSslCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OpenSslPath,

        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    & $OpenSslPath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
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
$integrationPort = 18884
$integrationUsername = "integration-client"
$mosquittoImage = "eclipse-mosquitto:2"
$integrationEnvironmentNames = @(
    "MQTT_INTEGRATION_CONFIG_DIR",
    "MQTT_INTEGRATION_CERT_DIR",
    "MQTT_INTEGRATION_HOST",
    "MQTT_INTEGRATION_PORT",
    "MQTT_INTEGRATION_USERNAME",
    "MQTT_INTEGRATION_PASSWORD",
    "MQTT_INTEGRATION_CA_FILE",
    "MQTT_INTEGRATION_UNTRUSTED_CA_FILE"
)

$projectRoot = $null
$pythonPath = $null
$composePath = $null
$mosquittoFixturePath = $null
$aclFixturePath = $null
$opensslConfigPath = $null
$opensslPath = $null
$integrationTestPath = $null
$tempRoot = $null
$tempWorkDirectory = $null
$configDirectory = $null
$certificateDirectory = $null
$untrustedDirectory = $null
$composeEnvPath = $null
$integrationCaCertificatePath = $null
$serverCertificatePath = $null
$serverKeyPath = $null
$untrustedCaCertificatePath = $null
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
    $opensslConfigPath = Join-Path $projectRoot "lab\tls\openssl.cnf"
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
        $opensslConfigPath,
        $integrationTestPath
    )
    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Required integration-test file was not found: $requiredFile"
        }
    }

    $opensslCommand = Get-Command openssl `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $opensslCommand) {
        $opensslPath = $opensslCommand.Source
    }
    else {
        $gitCommand = Get-Command git `
            -CommandType Application `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $gitCommand) {
            $gitCommandDirectory = Split-Path -Parent $gitCommand.Source
            $gitCommandDirectoryName = Split-Path -Leaf $gitCommandDirectory
            if ($gitCommandDirectoryName -in @("cmd", "bin")) {
                $gitRoot = Split-Path -Parent $gitCommandDirectory
                $gitOpenSslPath = Join-Path $gitRoot "usr\bin\openssl.exe"
                if (Test-Path -LiteralPath $gitOpenSslPath -PathType Leaf) {
                    $opensslPath = $gitOpenSslPath
                }
            }
        }
    }

    if ($null -eq $opensslPath) {
        throw "OpenSSL was not found in PATH or in the current Git for Windows installation."
    }

    Invoke-OpenSslCommand `
        -OpenSslPath $opensslPath `
        -ArgumentList @("version") `
        -FailureMessage "Failed to read the OpenSSL version."

    if (Test-LocalPortInUse -Port $integrationPort) {
        throw "Integration port $integrationHost`:$integrationPort is already in use; refusing to connect to or reuse an unknown service."
    }

    if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        throw "The system TEMP directory is not configured."
    }

    $tempRoot = (Resolve-Path -LiteralPath $env:TEMP).Path
    $tempWorkDirectory = Join-Path $tempRoot "mqtt-auth-integration-$runId"
    $configDirectory = Join-Path $tempWorkDirectory "config"
    $certificateDirectory = Join-Path $tempWorkDirectory "certs"
    $untrustedDirectory = Join-Path $tempWorkDirectory "untrusted"
    $composeEnvPath = Join-Path $tempWorkDirectory "compose.env"

    foreach ($temporaryDirectory in @(
        $configDirectory,
        $certificateDirectory,
        $untrustedDirectory
    )) {
        New-Item `
            -ItemType Directory `
            -Path $temporaryDirectory `
            -ErrorAction Stop |
            Out-Null
    }
    Copy-Item -LiteralPath $mosquittoFixturePath -Destination $configDirectory -ErrorAction Stop
    Copy-Item -LiteralPath $aclFixturePath -Destination $configDirectory -ErrorAction Stop

    $integrationCaKeyPath = Join-Path $certificateDirectory "ca.key"
    $integrationCaCertificatePath = Join-Path $certificateDirectory "ca.crt"
    $integrationCaSerialPath = Join-Path $certificateDirectory "ca.srl"
    $serverKeyPath = Join-Path $certificateDirectory "server.key"
    $serverCsrPath = Join-Path $certificateDirectory "server.csr"
    $serverCertificatePath = Join-Path $certificateDirectory "server.crt"
    $untrustedCaKeyPath = Join-Path $untrustedDirectory "ca.key"
    $untrustedCaCertificatePath = Join-Path $untrustedDirectory "ca.crt"

    Write-Host "Generating temporary integration TLS certificates..."
    Invoke-OpenSslCommand `
        -OpenSslPath $opensslPath `
        -ArgumentList @(
            "genrsa",
            "-out", $integrationCaKeyPath,
            "2048"
        ) `
        -FailureMessage "Failed to generate the temporary integration CA private key."

    Invoke-OpenSslCommand `
        -OpenSslPath $opensslPath `
        -ArgumentList @(
            "req", "-x509", "-new", "-sha256",
            "-key", $integrationCaKeyPath,
            "-out", $integrationCaCertificatePath,
            "-days", "3650",
            "-subj", "/CN=MQTT Integration Test CA",
            "-addext", "basicConstraints=critical,CA:TRUE",
            "-addext", "keyUsage=critical,keyCertSign,cRLSign"
        ) `
        -FailureMessage "Failed to generate the temporary integration CA certificate."

    Invoke-OpenSslCommand `
        -OpenSslPath $opensslPath `
        -ArgumentList @(
            "genrsa",
            "-out", $serverKeyPath,
            "2048"
        ) `
        -FailureMessage "Failed to generate the temporary integration server private key."

    Invoke-OpenSslCommand `
        -OpenSslPath $opensslPath `
        -ArgumentList @(
            "req", "-new", "-sha256",
            "-key", $serverKeyPath,
            "-out", $serverCsrPath,
            "-config", $opensslConfigPath
        ) `
        -FailureMessage "Failed to generate the temporary integration server CSR."

    Invoke-OpenSslCommand `
        -OpenSslPath $opensslPath `
        -ArgumentList @(
            "x509", "-req",
            "-in", $serverCsrPath,
            "-CA", $integrationCaCertificatePath,
            "-CAkey", $integrationCaKeyPath,
            "-CAcreateserial",
            "-CAserial", $integrationCaSerialPath,
            "-out", $serverCertificatePath,
            "-days", "825",
            "-sha256",
            "-extfile", $opensslConfigPath,
            "-extensions", "server_certificate"
        ) `
        -FailureMessage "Failed to sign the temporary integration server certificate."

    Invoke-OpenSslCommand `
        -OpenSslPath $opensslPath `
        -ArgumentList @(
            "genrsa",
            "-out", $untrustedCaKeyPath,
            "2048"
        ) `
        -FailureMessage "Failed to generate the temporary untrusted CA private key."

    Invoke-OpenSslCommand `
        -OpenSslPath $opensslPath `
        -ArgumentList @(
            "req", "-x509", "-new", "-sha256",
            "-key", $untrustedCaKeyPath,
            "-out", $untrustedCaCertificatePath,
            "-days", "3650",
            "-subj", "/CN=MQTT Integration Untrusted CA",
            "-addext", "basicConstraints=critical,CA:TRUE",
            "-addext", "keyUsage=critical,keyCertSign,cRLSign"
        ) `
        -FailureMessage "Failed to generate the temporary untrusted CA certificate."

    $expectedTlsPaths = @(
        $integrationCaKeyPath,
        $integrationCaCertificatePath,
        $integrationCaSerialPath,
        $serverKeyPath,
        $serverCsrPath,
        $serverCertificatePath,
        $untrustedCaKeyPath,
        $untrustedCaCertificatePath
    )
    foreach ($expectedTlsPath in $expectedTlsPaths) {
        if (
            -not (Test-Path -LiteralPath $expectedTlsPath -PathType Leaf) -or
            (Get-Item -LiteralPath $expectedTlsPath).Length -le 0
        ) {
            throw "Expected temporary TLS output is missing or empty: $expectedTlsPath"
        }
    }

    Invoke-OpenSslCommand `
        -OpenSslPath $opensslPath `
        -ArgumentList @(
            "verify",
            "-CAfile", $integrationCaCertificatePath,
            $serverCertificatePath
        ) `
        -FailureMessage "The temporary integration server certificate failed CA verification."

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

    $certificateMountSpecification = "type=bind,source=$certificateDirectory,target=/mosquitto/certs"
    & docker run --rm `
        --mount $certificateMountSpecification `
        --entrypoint sh `
        $mosquittoImage `
        -c "chown 1883:1883 /mosquitto/certs/server.key && chmod 600 /mosquitto/certs/server.key" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set safe permissions on the temporary integration server private key."
    }

    $composeConfigPath = $configDirectory.Replace("\", "/")
    $composeCertificatePath = $certificateDirectory.Replace("\", "/")
    $composeEnvironmentLines = @(
        "MQTT_INTEGRATION_CONFIG_DIR=$composeConfigPath",
        "MQTT_INTEGRATION_CERT_DIR=$composeCertificatePath",
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
        "MQTT_INTEGRATION_CERT_DIR",
        $certificateDirectory,
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

        $tlsTimeoutMilliseconds = [Math]::Min(1000, $remainingMilliseconds)
        if (
            Test-TlsConnection `
                -PythonPath $pythonPath `
                -HostName $integrationHost `
                -Port $integrationPort `
                -CaFilePath $integrationCaCertificatePath `
                -TimeoutMilliseconds $tlsTimeoutMilliseconds
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
    [Environment]::SetEnvironmentVariable(
        "MQTT_INTEGRATION_CA_FILE",
        $integrationCaCertificatePath,
        "Process"
    )
    [Environment]::SetEnvironmentVariable(
        "MQTT_INTEGRATION_UNTRUSTED_CA_FILE",
        $untrustedCaCertificatePath,
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
