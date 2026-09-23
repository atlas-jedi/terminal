# aero-icon.ps1 - the Terminal Aero icon: a white prompt chevron and a red underscore cursor,
# on a black rounded square with a Windows 7-style gloss. It is drawn with WPF, natively at
# every size (heavier strokes and pixel-snapped bars when small), rather than scaled down.
#
# -Mode Export: writes res\terminal\images-Aero, mirroring res\terminal\images-Dev file by
#   file: same names, same pixel sizes, and the icon placed where the original icon is, with
#   the same area (the original is 4:3, ours is square). contrast-black/-white files get the
#   monochrome high contrast version. Also writes the three .ico files the executables embed.
# -Mode Sheet: renders the icon at real sizes on dark, light and glass backgrounds, to a PNG.
using namespace System.Windows
using namespace System.Windows.Media
using namespace System.Windows.Media.Imaging
param(
    [ValidateSet('Export', 'Sheet')][string]$Mode = 'Export',
    [string]$RefDir = (Join-Path $PSScriptRoot '..\res\terminal\images-Dev'),
    [string]$OutDir = (Join-Path $PSScriptRoot '..\res\terminal\images-Aero'),
    [string]$SheetPath = (Join-Path $env:TEMP 'terminal-aero-icon.png')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
Add-Type -TypeDefinition @"
public static class AeroIconPixels {
    // Bounding box {left, top, right, bottom} of the pixels more opaque than threshold, in a
    // BGRA32 buffer; {0, 0, -1, -1} if none.
    public static int[] AlphaBox(byte[] bgra, int width, int height, int threshold) {
        int l = width, t = height, r = -1, b = -1;
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++)
                if (bgra[(y * width + x) * 4 + 3] > threshold) {
                    if (x < l) l = x; if (x > r) r = x; if (y < t) t = y; if (y > b) b = y;
                }
        return r < 0 ? new int[] { 0, 0, -1, -1 } : new int[] { l, t, r, b };
    }
}
"@

$Black = '#FF0B0B0B'; $Red = '#FFE01B2F'; $White = '#FFFFFFFF'

function New-Brush([string]$hex) {
    $b = [SolidColorBrush]::new([ColorConverter]::ConvertFromString($hex)); $b.Freeze(); return $b
}
function New-Pen([Brush]$brush, [double]$width) {
    $p = [Pen]::new($brush, $width)
    $p.StartLineCap = 'Flat'; $p.EndLineCap = 'Flat'; $p.LineJoin = 'Miter'; $p.MiterLimit = 10
    $p.Freeze(); return $p
}

# Draws the icon so that its plate fills the square $box. $variant: normal, hc-black (white
# lines, for dark high contrast themes) or hc-white (black lines).
function Draw-Icon([DrawingContext]$dc, [Rect]$box, [string]$variant) {
    $side = $box.Width
    $x0 = $box.X; $y0 = $box.Y
    function P([double]$u, [double]$v) { return [Point]::new($x0 + $u * $side, $y0 + $v * $side) }
    # Bars snap to whole pixels, so they stay crisp at small sizes.
    function Bar([double]$u0, [double]$v0, [double]$u1, [double]$v1) {
        $l = [Math]::Round($x0 + $u0 * $side); $t = [Math]::Round($y0 + $v0 * $side)
        $r = [Math]::Max($l + 1, [Math]::Round($x0 + $u1 * $side)); $b = [Math]::Max($t + 1, [Math]::Round($y0 + $v1 * $side))
        return [Rect]::new($l, $t, $r - $l, $b - $t)
    }
    # Proportional stroke, but never thinner than ~2px.
    $stroke = [Math]::Max($(if ($side -le 15) { 1.6 } else { 2.0 }), 0.12 * $side)
    $radius = 0.217 * $side

    $chevron = [StreamGeometry]::new()
    $ctx = $chevron.Open()
    $ctx.BeginFigure((P 0.237 0.283), $false, $false)
    $ctx.LineTo((P 0.489 0.500), $true, $false)
    $ctx.LineTo((P 0.237 0.717), $true, $false)
    $ctx.Close(); $chevron.Freeze()
    $cursor = Bar 0.534 0.637 0.809 0.740

    if ($variant -eq 'normal') {
        $plate = [RectangleGeometry]::new($box, $radius, $radius); $plate.Freeze()
        $dc.DrawGeometry((New-Brush $Black), $null, $plate)
        if ($side -ge 28) {
            $gloss = [LinearGradientBrush]::new()
            $gloss.StartPoint = [Point]::new(0, 0); $gloss.EndPoint = [Point]::new(0, 1)
            $gloss.GradientStops.Add([GradientStop]::new([Color]::FromArgb(0x40, 255, 255, 255), 0.0))
            $gloss.GradientStops.Add([GradientStop]::new([Color]::FromArgb(0x14, 255, 255, 255), 0.46))
            $gloss.GradientStops.Add([GradientStop]::new([Color]::FromArgb(0x00, 255, 255, 255), 0.47))
            $gloss.Freeze()
            $dc.PushClip($plate)
            $dc.DrawRectangle($gloss, $null, $box)
            $dc.Pop()
        }
        $dc.DrawGeometry($null, (New-Pen (New-Brush $White) $stroke), $chevron)
        $dc.DrawRectangle((New-Brush $Red), $null, $cursor)
    }
    else {
        # High contrast: a single color, the plate as an outline.
        $ink = New-Brush $(if ($variant -eq 'hc-black') { $White } else { $Black })
        $line = [Math]::Max(1.0, [Math]::Round(0.055 * $side))
        $inset = [Rect]::new($box.X + $line / 2, $box.Y + $line / 2, $side - $line, $side - $line)
        $dc.DrawRoundedRectangle($null, (New-Pen $ink $line), $inset, $radius, $radius)
        $dc.DrawGeometry($null, (New-Pen $ink $stroke), $chevron)
        $dc.DrawRectangle($ink, $null, $cursor)
    }
}

function New-Canvas([int]$width, [int]$height, [scriptblock]$draw) {
    $dv = [DrawingVisual]::new()
    $dc = $dv.RenderOpen()
    & $draw $dc
    $dc.Close()
    $rtb = [RenderTargetBitmap]::new($width, $height, 96, 96, [PixelFormats]::Pbgra32)
    $rtb.Render($dv); $rtb.Freeze()
    return $rtb
}
function Get-PngBytes([BitmapSource]$bmp) {
    $enc = [PngBitmapEncoder]::new()
    $enc.Frames.Add([BitmapFrame]::Create($bmp))
    $ms = [IO.MemoryStream]::new()
    $enc.Save($ms)
    # The comma keeps PowerShell from unrolling the array into loose bytes.
    return , $ms.ToArray()
}
function Read-Bgra([string]$path) {
    $dec = [BitmapDecoder]::Create([Uri]::new((Resolve-Path -LiteralPath $path).Path), 'PreservePixelFormat', 'OnLoad')
    $src = [FormatConvertedBitmap]::new($dec.Frames[0], [PixelFormats]::Bgra32, $null, 0)
    $w = $src.PixelWidth; $h = $src.PixelHeight
    $px = New-Object byte[] ($w * $h * 4)
    $src.CopyPixels($px, $w * 4, 0)
    return @{ Width = $w; Height = $h; Pixels = $px }
}

# Where our icon goes in a canvas: centered on the original icon, with the same area.
function Get-IconBox([string]$refPath) {
    $ref = Read-Bgra $refPath
    $a = [AeroIconPixels]::AlphaBox($ref.Pixels, $ref.Width, $ref.Height, 16)
    $bw = $a[2] - $a[0] + 1; $bh = $a[3] - $a[1] + 1
    $side = [Math]::Min([Math]::Min($ref.Width, $ref.Height), [Math]::Round([Math]::Sqrt($bw * $bh)))
    $left = [Math]::Min($ref.Width - $side, [Math]::Max(0, [Math]::Round($a[0] + $bw / 2.0 - $side / 2.0)))
    $top = [Math]::Min($ref.Height - $side, [Math]::Max(0, [Math]::Round($a[1] + $bh / 2.0 - $side / 2.0)))
    return @{ Width = $ref.Width; Height = $ref.Height; Box = [Rect]::new($left, $top, $side, $side) }
}
function Get-Variant([string]$name) {
    if ($name -match 'contrast-black') { return 'hc-black' }
    if ($name -match 'contrast-white') { return 'hc-white' }
    return 'normal'
}

# An .ico file: BMP frames (32bpp with an AND mask) below 256, a PNG frame at 256, like the
# original ones.
function Write-Ico([string]$path, [object[]]$frames) {
    $images = foreach ($f in $frames) {
        $bmp = $f.Bitmap; $n = $bmp.PixelWidth
        if ($n -ge 256) { , (Get-PngBytes $bmp) }
        else {
            $px = New-Object byte[] ($n * $n * 4)
            ([FormatConvertedBitmap]::new($bmp, [PixelFormats]::Bgra32, $null, 0)).CopyPixels($px, $n * 4, 0)
            $maskStride = [int]([Math]::Ceiling($n / 32.0) * 4)
            $ms = [IO.MemoryStream]::new(); $w = [IO.BinaryWriter]::new($ms)
            $w.Write([uint32]40); $w.Write([int32]$n); $w.Write([int32]($n * 2)); $w.Write([uint16]1); $w.Write([uint16]32)
            $w.Write([uint32]0); $w.Write([uint32]($n * $n * 4 + $maskStride * $n)); $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
            for ($y = $n - 1; $y -ge 0; $y--) { $w.Write($px, $y * $n * 4, $n * 4) }
            for ($y = $n - 1; $y -ge 0; $y--) {
                $row = New-Object byte[] $maskStride
                for ($x = 0; $x -lt $n; $x++) { if ($px[($y * $n + $x) * 4 + 3] -eq 0) { $row[[Math]::Floor($x / 8)] = $row[[Math]::Floor($x / 8)] -bor (0x80 -shr ($x % 8)) } }
                $w.Write($row)
            }
            $w.Flush(); , $ms.ToArray()
        }
    }
    $out = [IO.MemoryStream]::new(); $w = [IO.BinaryWriter]::new($out)
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$frames.Count)
    $offset = 6 + 16 * $frames.Count
    for ($i = 0; $i -lt $frames.Count; $i++) {
        $n = $frames[$i].Bitmap.PixelWidth
        $w.Write([byte]($n % 256)); $w.Write([byte]($n % 256)); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$images[$i].Length); $w.Write([uint32]$offset)
        $offset += $images[$i].Length
    }
    foreach ($img in $images) { $w.Write([byte[]]$img) }
    $w.Flush()
    if ($out.Length -ne $offset) { throw "$path`: wrote $($out.Length) bytes, the directory says $offset" }
    [IO.File]::WriteAllBytes($path, $out.ToArray())
}

if ($Mode -eq 'Export') {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $count = 0
    foreach ($ref in Get-ChildItem -LiteralPath $RefDir -Filter '*.png') {
        $place = Get-IconBox $ref.FullName
        $variant = Get-Variant $ref.Name
        $bmp = New-Canvas $place.Width $place.Height { param($dc) Draw-Icon $dc $place.Box $variant }
        [IO.File]::WriteAllBytes((Join-Path $OutDir $ref.Name), (Get-PngBytes $bmp))
        $count++
    }
    foreach ($ico in @(@('terminal.ico', 'normal', '_altform-unplated'), @('terminal_contrast-black.ico', 'hc-black', '_contrast-black'), @('terminal_contrast-white.ico', 'hc-white', '_contrast-white'))) {
        $frames = foreach ($n in 16, 20, 24, 32, 48, 64, 256) {
            $refPng = Join-Path $RefDir ("Square44x44Logo.targetsize-{0}{1}.png" -f $n, $ico[2])
            if (-not (Test-Path -LiteralPath $refPng)) { $refPng = Join-Path $RefDir ("Square44x44Logo.targetsize-{0}.png" -f $n) }
            $place = Get-IconBox $refPng
            $variant = $ico[1]
            @{ Bitmap = (New-Canvas $n $n { param($dc) Draw-Icon $dc $place.Box $variant }) }
        }
        Write-Ico (Join-Path $OutDir $ico[0]) $frames
        $count++
    }
    Write-Host "[aero-icon] $count files written to $((Resolve-Path -LiteralPath $OutDir).Path)"
}
else {
    $sizes = @(256, 64, 48, 32, 24, 20, 16)
    $backs = @('#FF1F1F1F', '#FFEFEFEF', '#FF9DB9DC')
    $width = 20 + ($sizes | Measure-Object -Sum).Sum + 10 * $sizes.Count
    $sheet = New-Canvas $width (3 * 280) {
        param($dc)
        for ($i = 0; $i -lt $backs.Count; $i++) {
            $dc.DrawRectangle((New-Brush $backs[$i]), $null, [Rect]::new(0, $i * 280, $width, 280))
            $x = 10
            foreach ($n in $sizes) {
                $m = [Math]::Max(1, [Math]::Round($n / 16.0))
                Draw-Icon $dc ([Rect]::new($x + $m, $i * 280 + 12 + $m, $n - 2 * $m, $n - 2 * $m)) 'normal'
                $x += $n + 10
            }
        }
    }
    [IO.File]::WriteAllBytes($SheetPath, (Get-PngBytes $sheet))
    Write-Host "[aero-icon] sheet: $SheetPath"
}
