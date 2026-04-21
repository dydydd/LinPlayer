$ErrorActionPreference = 'Stop'

$buildName = $env:BUILD_NAME_INPUT
$buildNumber = $env:BUILD_NUMBER_INPUT
$versionFullInput = $env:VERSION_FULL_INPUT

function Get-BuildNumberFromGit {
  $gitRef = if ([string]::IsNullOrWhiteSpace($env:GITHUB_SHA)) { 'HEAD' } else { $env:GITHUB_SHA }
  $commitEpoch = ''

  try {
    $commitEpoch = (git show -s --format=%ct $gitRef 2>$null).Trim()
  } catch {
  }

  if ([string]::IsNullOrWhiteSpace($commitEpoch)) {
    try {
      $commitEpoch = (git show -s --format=%ct HEAD 2>$null).Trim()
    } catch {
    }
  }

  if ($commitEpoch -notmatch '^[0-9]+$') {
    return $null
  }

  $dt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$commitEpoch).UtcDateTime
  # Keep Android versionCode within signed 32-bit int range while still making the
  # default CI build number stable across jobs and independent of workflow run counters.
  return ('{0:00}{1:000}{2:00}{3:00}' -f ($dt.Year % 100), $dt.DayOfYear, $dt.Hour, $dt.Minute)
}

if (-not [string]::IsNullOrWhiteSpace($versionFullInput)) {
  if ($versionFullInput -match '\+') {
    $parts = $versionFullInput -split '\+', 2
    $buildName = $parts[0]
    $buildNumber = $parts[1]
    if ([string]::IsNullOrWhiteSpace($buildName)) {
      throw "VERSION_FULL_INPUT build name is empty (got: $versionFullInput)"
    }
  } else {
    # Accept "1.2.3" and treat it as a build name override. buildNumber is resolved later.
    $buildName = $versionFullInput
  }
}

$rawVersion = ''
if (Test-Path 'pubspec.yaml') {
  $versionLine = Get-Content 'pubspec.yaml' | Where-Object { $_ -match '^\s*version:\s*' } | Select-Object -First 1
  if ($versionLine) {
    $rawVersion = ($versionLine -replace '^\s*version:\s*', '').Trim()
  }
}

if ([string]::IsNullOrWhiteSpace($buildName) -and -not [string]::IsNullOrWhiteSpace($rawVersion)) {
  $buildName = ($rawVersion -split '\+')[0]
}
if ([string]::IsNullOrWhiteSpace($buildName)) {
  $buildName = '0.1.0'
}

if ([string]::IsNullOrWhiteSpace($buildNumber)) {
  $buildNumber = Get-BuildNumberFromGit
}
if ([string]::IsNullOrWhiteSpace($buildNumber)) {
  $buildNumber = $env:GITHUB_RUN_NUMBER
}
if ([string]::IsNullOrWhiteSpace($buildNumber) -and -not [string]::IsNullOrWhiteSpace($rawVersion) -and ($rawVersion -match '\+')) {
  $buildNumber = ($rawVersion -split '\+')[-1]
}
if ([string]::IsNullOrWhiteSpace($buildNumber)) {
  $buildNumber = '1'
}
if ($buildNumber -notmatch '^[0-9]+$') {
  throw "build_number must be an integer (got: $buildNumber)"
}

$versionFull = "$buildName+$buildNumber"
$appVersion = "$buildName.$buildNumber"

Write-Host "Using version: $versionFull"

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_ENV)) {
  Add-Content -Path $env:GITHUB_ENV -Value "BUILD_NAME=$buildName"
  Add-Content -Path $env:GITHUB_ENV -Value "BUILD_NUMBER=$buildNumber"
  Add-Content -Path $env:GITHUB_ENV -Value "VERSION_FULL=$versionFull"
  Add-Content -Path $env:GITHUB_ENV -Value "APP_VERSION=$appVersion"
  Add-Content -Path $env:GITHUB_ENV -Value "APP_VERSION_FULL=$versionFull"
} else {
  Write-Output "BUILD_NAME=$buildName"
  Write-Output "BUILD_NUMBER=$buildNumber"
  Write-Output "VERSION_FULL=$versionFull"
  Write-Output "APP_VERSION=$appVersion"
  Write-Output "APP_VERSION_FULL=$versionFull"
}
