$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composePath = Join-Path $projectRoot "compose.yaml"

if (-not (Get-Command docker -CommandType Application -ErrorAction SilentlyContinue)) {
    Write-Error "Docker command was not found."
    exit 1
}

docker compose version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker Compose is not available."
    exit 1
}

if (-not (Test-Path -LiteralPath $composePath -PathType Leaf)) {
    Write-Error "Docker Compose file was not found: $composePath"
    exit 1
}

Push-Location $projectRoot
try {
    Write-Host "Stopping local MQTT lab..."
    docker compose down
    $composeExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

exit $composeExitCode
