# Run this script after installing Flutter SDK and adding flutter/bin to PATH.
# Python .venv is unrelated to Flutter and may stay activated.
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter was not found in PATH. Reopen the terminal after installing Flutter.'
}

Push-Location -LiteralPath $projectPath
try {
    flutter create --empty --platforms=windows,android --project-name worknotes .
    if ($LASTEXITCODE -ne 0) { throw 'flutter create failed.' }

    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }

    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }
}
finally {
    Pop-Location
}
