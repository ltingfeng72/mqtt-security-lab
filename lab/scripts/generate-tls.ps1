param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$opensslConfigPath = Join-Path $projectRoot "lab\tls\openssl.cnf"
$generatedDirectory = Join-Path $projectRoot "lab\tls\generated"
$managedFileNames = @(
    "ca.key",
    "ca.crt",
    "ca.srl",
    "server.key",
    "server.csr",
    "server.crt"
)

$opensslPath = $null
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
    [Console]::Error.WriteLine(
        "OpenSSL was not found in PATH or in the current Git for Windows installation."
    )
    exit 1
}

Write-Host "Using OpenSSL: $opensslPath"
$opensslVersion = & $opensslPath version
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("Failed to read the OpenSSL version.")
    exit 1
}
Write-Host "OpenSSL version: $($opensslVersion -join ' ')"

if (-not (Test-Path -LiteralPath $opensslConfigPath -PathType Leaf)) {
    [Console]::Error.WriteLine("OpenSSL configuration was not found: {0}", $opensslConfigPath)
    exit 1
}

$locationPushed = $false
$exitCode = 1

try {
    Push-Location $projectRoot
    $locationPushed = $true

    if (Test-Path -LiteralPath $generatedDirectory) {
        $generatedDirectoryItem = Get-Item -LiteralPath $generatedDirectory
        if (-not $generatedDirectoryItem.PSIsContainer) {
            throw "TLS generated path exists but is not a directory: $generatedDirectory"
        }
    }
    else {
        New-Item -ItemType Directory -Path $generatedDirectory -ErrorAction Stop | Out-Null
    }

    $managedPaths = @(
        $managedFileNames | ForEach-Object {
            Join-Path $generatedDirectory $_
        }
    )
    $existingManagedPaths = @(
        $managedPaths | Where-Object {
            Test-Path -LiteralPath $_
        }
    )

    if ($existingManagedPaths.Count -gt 0 -and -not $Force) {
        throw "TLS generated files already exist. Use -Force to replace only the managed TLS files."
    }

    if ($Force) {
        foreach ($managedPath in $existingManagedPaths) {
            $managedItem = Get-Item -LiteralPath $managedPath
            if ($managedItem.PSIsContainer) {
                throw "Refusing to remove a directory at a managed TLS file path: $managedPath"
            }

            Remove-Item -LiteralPath $managedPath -Force -ErrorAction Stop
        }
    }

    $caKeyPath = Join-Path $generatedDirectory "ca.key"
    $caCertificatePath = Join-Path $generatedDirectory "ca.crt"
    $caSerialPath = Join-Path $generatedDirectory "ca.srl"
    $serverKeyPath = Join-Path $generatedDirectory "server.key"
    $serverCsrPath = Join-Path $generatedDirectory "server.csr"
    $serverCertificatePath = Join-Path $generatedDirectory "server.crt"

    Write-Host "Generating local CA private key..."
    & $opensslPath genrsa -out $caKeyPath 2048
    if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL failed while generating the CA private key."
    }

    Write-Host "Generating local CA certificate..."
    & $opensslPath req `
        -x509 `
        -new `
        -sha256 `
        -key $caKeyPath `
        -out $caCertificatePath `
        -days 3650 `
        -subj "/CN=MQTT Local Lab CA" `
        -addext "basicConstraints=critical,CA:TRUE" `
        -addext "keyUsage=critical,keyCertSign,cRLSign"
    if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL failed while generating the CA certificate."
    }

    Write-Host "Generating Broker server private key..."
    & $opensslPath genrsa -out $serverKeyPath 2048
    if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL failed while generating the server private key."
    }

    Write-Host "Generating Broker server certificate request..."
    & $opensslPath req `
        -new `
        -sha256 `
        -key $serverKeyPath `
        -out $serverCsrPath `
        -config $opensslConfigPath
    if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL failed while generating the server certificate request."
    }

    Write-Host "Signing Broker server certificate..."
    & $opensslPath x509 `
        -req `
        -in $serverCsrPath `
        -CA $caCertificatePath `
        -CAkey $caKeyPath `
        -CAcreateserial `
        -CAserial $caSerialPath `
        -out $serverCertificatePath `
        -days 825 `
        -sha256 `
        -extfile $opensslConfigPath `
        -extensions server_certificate
    if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL failed while signing the server certificate."
    }

    foreach ($managedPath in $managedPaths) {
        if (
            -not (Test-Path -LiteralPath $managedPath -PathType Leaf) -or
            (Get-Item -LiteralPath $managedPath).Length -le 0
        ) {
            throw "Expected TLS output is missing or empty: $managedPath"
        }
    }

    Write-Host "TLS certificates generated successfully."
    Write-Host "Generated files: $generatedDirectory"
    $exitCode = 0
}
catch {
    [Console]::Error.WriteLine("TLS certificate generation failed: {0}", $_.Exception.Message)
    $exitCode = 1
}
finally {
    if ($locationPushed) {
        Pop-Location
    }
}

exit $exitCode
