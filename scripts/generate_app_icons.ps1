param(
  [string]$SourcePath = $(
    $root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $canonicalSource = Join-Path $root "assets/images/app_icon_source.png"
    if (Test-Path -LiteralPath $canonicalSource) {
      $canonicalSource
    }
    else {
      Join-Path $root "tubiaotouming.png"
    }
  )
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolvedSource = (Resolve-Path $SourcePath).Path

Add-Type -AssemblyName System.Drawing

function Save-ResizedPng {
  param(
    [Parameter(Mandatory = $true)]
    [System.Drawing.Image]$Image,
    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,
    [Parameter(Mandatory = $true)]
    [int]$Size
  )

  $directory = Split-Path -Parent $DestinationPath
  if ($directory) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }

  $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

  try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.DrawImage(
      $Image,
      [System.Drawing.Rectangle]::new(0, 0, $Size, $Size),
      [System.Drawing.Rectangle]::new(0, 0, $Image.Width, $Image.Height),
      [System.Drawing.GraphicsUnit]::Pixel
    )
    $bitmap.Save($DestinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

$androidSizes = [ordered]@{
  "mipmap-mdpi"    = 48
  "mipmap-hdpi"    = 72
  "mipmap-xhdpi"   = 96
  "mipmap-xxhdpi"  = 144
  "mipmap-xxxhdpi" = 192
}

$macosIcons = [ordered]@{
  "app_icon_16.png"   = 16
  "app_icon_32.png"   = 32
  "app_icon_64.png"   = 64
  "app_icon_128.png"  = 128
  "app_icon_256.png"  = 256
  "app_icon_512.png"  = 512
  "app_icon_1024.png" = 1024
}

$canonicalSourcePath = Join-Path $root "assets/images/app_icon_source.png"
if (([System.IO.Path]::GetFullPath($resolvedSource)) -ne ([System.IO.Path]::GetFullPath($canonicalSourcePath))) {
  Copy-Item -LiteralPath $resolvedSource -Destination $canonicalSourcePath -Force
}

$image = [System.Drawing.Image]::FromFile($resolvedSource)

try {
  if ($image.Width -ne $image.Height) {
    throw "Source image must be square. Got $($image.Width)x$($image.Height)."
  }

  foreach ($entry in $androidSizes.GetEnumerator()) {
    $destination = Join-Path $root "android/app/src/main/res/$($entry.Key)/ic_launcher.png"
    Save-ResizedPng -Image $image -DestinationPath $destination -Size $entry.Value
  }

  $macosIconDir = Join-Path $root "macos/Runner/Assets.xcassets/AppIcon.appiconset"
  foreach ($entry in $macosIcons.GetEnumerator()) {
    $destination = Join-Path $macosIconDir $entry.Key
    Save-ResizedPng -Image $image -DestinationPath $destination -Size $entry.Value
  }
}
finally {
  $image.Dispose()
}

$windowsSource = Join-Path $root "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png"
$windowsTarget = Join-Path $root "windows/runner/resources/app_icon.ico"

& python (Join-Path $root "scripts/update_windows_icon.py") --png $windowsSource --ico $windowsTarget
if ($LASTEXITCODE -ne 0) {
  throw "Failed to generate Windows icon."
}

Write-Host "Updated app icons from $resolvedSource"
