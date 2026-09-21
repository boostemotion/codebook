$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$windowsResourceDirectory = Join-Path $repositoryRoot 'windows\runner\resources'
$masterPath = Join-Path $windowsResourceDirectory 'app_icon.png'
$masterSize = 1024

function New-RoundedPath {
    param(
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [int]$Radius
    )
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-IconBitmap {
    param([int]$Size)

    $bitmap = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $scale = $Size / 1024.0
    $blue = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 37, 99, 235))
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $keyhole = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 37, 99, 235))
    $background = New-RoundedPath -X ([int](48 * $scale)) -Y ([int](48 * $scale)) -Width ([int](928 * $scale)) -Height ([int](928 * $scale)) -Radius ([int](208 * $scale))
    $graphics.FillPath($blue, $background)

    $shacklePen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [float](76 * $scale))
    $shacklePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $shacklePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawArc($shacklePen, [int](315 * $scale), [int](190 * $scale), [int](394 * $scale), [int](394 * $scale), 180, 180)

    $lockBody = New-RoundedPath -X ([int](245 * $scale)) -Y ([int](420 * $scale)) -Width ([int](534 * $scale)) -Height ([int](370 * $scale)) -Radius ([int](70 * $scale))
    $graphics.FillPath($white, $lockBody)
    $graphics.FillEllipse($keyhole, [int](474 * $scale), [int](515 * $scale), [int](76 * $scale), [int](76 * $scale))
    $graphics.FillRectangle($keyhole, [int](500 * $scale), [int](570 * $scale), [int](24 * $scale), [int](105 * $scale))

    $background.Dispose()
    $lockBody.Dispose()
    $shacklePen.Dispose()
    $blue.Dispose()
    $white.Dispose()
    $keyhole.Dispose()
    $graphics.Dispose()
    return $bitmap
}

New-Item -ItemType Directory -Path $windowsResourceDirectory -Force | Out-Null
$master = New-IconBitmap -Size $masterSize
$master.Save($masterPath, [System.Drawing.Imaging.ImageFormat]::Png)
$master.Dispose()

$androidSizes = @{
    'mipmap-mdpi' = 48
    'mipmap-hdpi' = 72
    'mipmap-xhdpi' = 96
    'mipmap-xxhdpi' = 144
    'mipmap-xxxhdpi' = 192
}
$androidRoot = Join-Path $repositoryRoot 'android\app\src\main\res'
foreach ($entry in $androidSizes.GetEnumerator()) {
    $directory = Join-Path $androidRoot $entry.Key
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $bitmap = New-IconBitmap -Size $entry.Value
    $bitmap.Save((Join-Path $directory 'ic_launcher.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}

$icoPath = Join-Path $windowsResourceDirectory 'app_icon.ico'
& ffmpeg.exe -y -loglevel error -i $masterPath -vf scale=256:256 -c:v bmp -pix_fmt bgra $icoPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $icoPath)) {
    throw 'Failed to create Windows icon.'
}
Remove-Item -LiteralPath $masterPath -Force
Write-Host "Created $icoPath and Android launcher icons."
