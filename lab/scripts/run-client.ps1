$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pythonPath = Join-Path $projectRoot ".venv\Scripts\python.exe"
$clientPath = Join-Path $projectRoot "src\mqtt_client.py"

if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
    Write-Error "Project virtual environment Python was not found: $pythonPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $clientPath -PathType Leaf)) {
    Write-Error "MQTT client was not found: $clientPath"
    exit 1
}

Push-Location $projectRoot
try {
    Write-Host "Running MQTT client..."
    & $pythonPath $clientPath
    $clientExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

exit $clientExitCode
