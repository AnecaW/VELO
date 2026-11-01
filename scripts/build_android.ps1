param([ValidateSet('lan','production')][string]$Mode = 'lan')
$ErrorActionPreference = 'Stop'
$veloRoot = Split-Path -Parent $PSScriptRoot
$veloConfig = Join-Path $veloRoot "config/$Mode.json"
if (-not (Test-Path -LiteralPath $veloConfig)) { throw "Missing operator build configuration: $veloConfig" }
$veloValues = Get-Content -LiteralPath $veloConfig -Raw | ConvertFrom-Json
$veloUri = [Uri]$veloValues.VELO_BACKEND_URL
if ($veloUri.UserInfo -or $veloUri.Query -or $veloUri.Fragment -or $veloUri.AbsolutePath -ne '/') { throw 'Use an origin without credentials or path.' }
if ($Mode -eq 'production' -and ($veloUri.Scheme -ne 'https' -or $veloUri.Host.EndsWith('.example.com') -or $veloUri.Host.EndsWith('.test') -or $veloValues.VELO_LAN_MODE -eq 'true')) { throw 'Production requires a real HTTPS origin and LAN mode disabled.' }
Push-Location $veloRoot
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    flutter build apk --release "--dart-define-from-file=$veloConfig"
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    New-Item -ItemType Directory -Force -Path (Join-Path $veloRoot 'dist') | Out-Null
    Copy-Item -LiteralPath (Join-Path $veloRoot 'build/app/outputs/flutter-apk/app-release.apk') -Destination (Join-Path $veloRoot "dist/velo-$Mode.apk")
} finally {
    Pop-Location
}
