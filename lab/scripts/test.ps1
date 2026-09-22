$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pythonPath = Join-Path $projectRoot ".venv\Scripts\python.exe"
$testsPath = Join-Path $projectRoot "tests"

if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
    Write-Error "Project virtual environment Python was not found: $pythonPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $testsPath -PathType Container)) {
    Write-Error "Test directory was not found: $testsPath"
    exit 1
}

Push-Location $projectRoot
try {
    Write-Host "Running pytest..."
    & $pythonPath -m pytest -q tests -p no:cacheprovider
    $pytestExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

exit $pytestExitCode
