[CmdletBinding()]
param()

$projectRoot = $PSScriptRoot
$flutterExe = if ($env:FLUTTER_ROOT) {
    Join-Path $env:FLUTTER_ROOT "bin\flutter.bat"
} else {
    "D:\flutter\bin\flutter.bat"
}

if (-not (Test-Path -LiteralPath $flutterExe)) {
    throw "Flutter was not found. Set FLUTTER_ROOT or install Flutter at D:\flutter."
}

if (-not $env:OFFICIAL_BRIDGE_PYTHON) {
    $env:OFFICIAL_BRIDGE_PYTHON = Join-Path `
        $env:LOCALAPPDATA `
        "Programs\Python\Python312\python.exe"
}
if (-not (Test-Path -LiteralPath $env:OFFICIAL_BRIDGE_PYTHON)) {
    throw "Python was not found. Set OFFICIAL_BRIDGE_PYTHON to python.exe."
}

if (-not $env:PROTOCOL_ANALYSIS_EXE) {
    $protocolCandidates = @(
        (Join-Path $projectRoot "flutter_app\build\windows\x64\runner\Release\ProtocolAnalysis.exe")
        (Join-Path $projectRoot "ProtocolAnalysis.exe")
    )
    $env:PROTOCOL_ANALYSIS_EXE = $protocolCandidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}
if (-not $env:PROTOCOL_ANALYSIS_EXE -or
    -not (Test-Path -LiteralPath $env:PROTOCOL_ANALYSIS_EXE)) {
    throw "ProtocolAnalysis.exe was not found. Set PROTOCOL_ANALYSIS_EXE first."
}

Write-Host "Python: $env:OFFICIAL_BRIDGE_PYTHON"
Write-Host "ProtocolAnalysis: $env:PROTOCOL_ANALYSIS_EXE"

Push-Location (Join-Path $projectRoot "flutter_app")
try {
    & $flutterExe run -d windows
    $flutterExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($flutterExitCode -ne 0) {
    throw "Flutter exited with code $flutterExitCode."
}
