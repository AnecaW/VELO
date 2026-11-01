$ErrorActionPreference = 'Stop'
$veloRoot = Split-Path -Parent $PSScriptRoot
Push-Location $veloRoot
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    flutter build apk --release --dart-define-from-file=config/supabase.json
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    New-Item -ItemType Directory -Force -Path (Join-Path $veloRoot 'dist') | Out-Null
    Copy-Item -LiteralPath (Join-Path $veloRoot 'build/app/outputs/flutter-apk/app-release.apk') -Destination (Join-Path $veloRoot 'dist/velo-supabase.apk')
} finally { Pop-Location }
