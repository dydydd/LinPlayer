param(
  [string]$BuildName,
  [string]$BuildNumber,
  [string]$TargetPlatform = 'android-arm64',
  [string]$OutDir = 'build/local-android-apks',
  [string]$SplitDebugInfoDir = 'build/symbols/android-phone',
  [switch]$SkipPubGet
)

$ErrorActionPreference = 'Stop'

function Get-VersionFromPubspec {
  if (-not (Test-Path 'pubspec.yaml')) { return $null }
  $versionLine = Get-Content 'pubspec.yaml' | Where-Object { $_ -match '^\s*version:\s*' } | Select-Object -First 1
  if (-not $versionLine) { return $null }
  return ($versionLine -replace '^\s*version:\s*', '').Trim()
}

function Resolve-BuildVersion {
  $raw = Get-VersionFromPubspec
  $resolvedName = $BuildName
  $resolvedNumber = $BuildNumber

  if ([string]::IsNullOrWhiteSpace($resolvedName) -and -not [string]::IsNullOrWhiteSpace($raw)) {
    $resolvedName = ($raw -split '\+')[0]
  }
  if ([string]::IsNullOrWhiteSpace($resolvedName)) {
    $resolvedName = '1.0.0'
  }

  if ([string]::IsNullOrWhiteSpace($resolvedNumber) -and -not [string]::IsNullOrWhiteSpace($raw) -and ($raw -match '\+')) {
    $resolvedNumber = ($raw -split '\+')[-1]
  }
  if ([string]::IsNullOrWhiteSpace($resolvedNumber)) {
    $resolvedNumber = '1'
  }
  if ($resolvedNumber -notmatch '^[0-9]+$') {
    throw "BuildNumber must be an integer. Current value: $resolvedNumber"
  }

  return @{
    Name = $resolvedName
    Number = $resolvedNumber
    Full = "$resolvedName+$resolvedNumber"
  }
}

Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$version = Resolve-BuildVersion
Write-Host "Using build version: $($version.Full)"

if (-not $SkipPubGet) {
  flutter pub get | Out-Host
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $SplitDebugInfoDir | Out-Null

$buildArgs = @(
  'build', 'apk', '--release',
  '--split-per-abi',
  '--target-platform', $TargetPlatform,
  '--split-debug-info', $SplitDebugInfoDir,
  '--build-name', $version.Name,
  '--build-number', $version.Number
)

& flutter @buildArgs
if ($LASTEXITCODE -ne 0) {
  throw "flutter build apk failed with exit code $LASTEXITCODE"
}

$suffix = switch ($TargetPlatform) {
  'android-arm64' { 'arm64-v8a' }
  'android-arm' { 'armeabi-v7a' }
  'android-x64' { 'x86_64' }
  'android-x86_64' { 'x86_64' }
  'android-x86' { 'x86' }
  default { throw "Unsupported TargetPlatform: $TargetPlatform" }
}

$src = "build/app/outputs/flutter-apk/app-$suffix-release.apk"
$dst = Join-Path $OutDir "LinPlayer-Android-PHONE-$suffix.apk"
if (-not (Test-Path $src)) {
  throw "APK output missing: $src"
}

Copy-Item -Path $src -Destination $dst -Force

$outPath = (Resolve-Path $OutDir).Path
$symbolsPath = (Resolve-Path $SplitDebugInfoDir).Path
Write-Host ""
Write-Host "Output folder: $outPath"
Write-Host "Symbol folder: $symbolsPath"
