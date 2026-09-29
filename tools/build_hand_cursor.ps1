Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourcePath = Join-Path $projectRoot 'outputs/cursor-hand-set-20260920/source-sheet.png'
$targetRoot = Join-Path $projectRoot 'assets/art/ui/hand_cursor'
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null

$states = @(
    @{ Name = 'normal'; SourceX = 78; SourceY = 34; SourceWidth = 593; SourceHeight = 667; TipX = 40.0; TipY = 44.0; HotspotX = 24.0; HotspotY = 24.0 },
    @{ Name = 'hover'; SourceX = 607; SourceY = 32; SourceWidth = 593; SourceHeight = 669; TipX = 41.0; TipY = 46.0; HotspotX = 24.0; HotspotY = 24.0 },
    @{ Name = 'pressed'; SourceX = 1231; SourceY = 93; SourceWidth = 572; SourceHeight = 610; TipX = 42.0; TipY = 46.0; HotspotX = 24.0; HotspotY = 24.0 },
    @{ Name = 'drag'; SourceX = 1715; SourceY = 106; SourceWidth = 453; SourceHeight = 557; TipX = 18.0; TipY = 46.0; HotspotX = 24.0; HotspotY = 24.0 }
)

$sheet = [System.Drawing.Bitmap]::new($sourcePath)
$canvasSize = 256
$outlineRadius = 5
foreach ($state in $states) {
    $target = [System.Drawing.Bitmap]::new($canvasSize, $canvasSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($target)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $factor = 220.0 / ($state.SourceHeight - 1.0)
    $destination = [System.Drawing.RectangleF]::new(
        ($state.HotspotX - $state.TipX * $factor),
        ($state.HotspotY - $state.TipY * $factor),
        ($state.SourceWidth * $factor),
        ($state.SourceHeight * $factor)
    )
    $source = [System.Drawing.Rectangle]::new($state.SourceX, $state.SourceY, $state.SourceWidth, $state.SourceHeight)
    $graphics.DrawImage($sheet, $destination, $source, [System.Drawing.GraphicsUnit]::Pixel)
    $graphics.Dispose()

    $visited = [bool[]]::new($canvasSize * $canvasSize)
    $largestComponent = [System.Collections.Generic.List[int]]::new()
    for ($startY = 0; $startY -lt $canvasSize; $startY++) {
        for ($startX = 0; $startX -lt $canvasSize; $startX++) {
            $startIndex = $startY * $canvasSize + $startX
            if ($visited[$startIndex] -or $target.GetPixel($startX, $startY).A -le 8) { continue }
            $component = [System.Collections.Generic.List[int]]::new()
            $queue = [System.Collections.Generic.Queue[int]]::new()
            $queue.Enqueue($startIndex)
            $visited[$startIndex] = $true
            while ($queue.Count -gt 0) {
                $index = $queue.Dequeue()
                $component.Add($index)
                $currentX = $index % $canvasSize
                $currentY = [Math]::Floor($index / $canvasSize)
                for ($neighborY = [Math]::Max(0, $currentY - 1); $neighborY -le [Math]::Min($canvasSize - 1, $currentY + 1); $neighborY++) {
                    for ($neighborX = [Math]::Max(0, $currentX - 1); $neighborX -le [Math]::Min($canvasSize - 1, $currentX + 1); $neighborX++) {
                        $neighborIndex = $neighborY * $canvasSize + $neighborX
                        if ($visited[$neighborIndex] -or $target.GetPixel($neighborX, $neighborY).A -le 8) { continue }
                        $visited[$neighborIndex] = $true
                        $queue.Enqueue($neighborIndex)
                    }
                }
            }
            if ($component.Count -gt $largestComponent.Count) {
                $largestComponent = $component
            }
        }
    }
    $keep = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($index in $largestComponent) { [void]$keep.Add($index) }
    for ($y = 0; $y -lt $canvasSize; $y++) {
        for ($x = 0; $x -lt $canvasSize; $x++) {
            if (-not $keep.Contains($y * $canvasSize + $x)) {
                $target.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
            }
        }
    }

    for ($y = 0; $y -lt $canvasSize; $y++) {
        for ($x = 0; $x -lt $canvasSize; $x++) {
            $pixel = $target.GetPixel($x, $y)
            if ($pixel.A -eq 0) { continue }
            $luma = 0.2126 * $pixel.R + 0.7152 * $pixel.G + 0.0722 * $pixel.B
            $factorDark = if ($luma -lt 115) { 0.72 } elseif ($luma -lt 205) { 0.90 } else { 0.98 }
            $red = [Math]::Min(255, [Math]::Round($pixel.R * $factorDark))
            $green = [Math]::Min(255, [Math]::Round($pixel.G * $factorDark))
            $blue = [Math]::Min(255, [Math]::Round($pixel.B * $factorDark))
            $alpha = if ($pixel.A -gt 8) { 255 } else { 0 }
            $target.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $red, $green, $blue))
        }
    }

    $outlined = [System.Drawing.Bitmap]::new($canvasSize, $canvasSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $canvasSize; $y++) {
        for ($x = 0; $x -lt $canvasSize; $x++) {
            $pixel = $target.GetPixel($x, $y)
            $luma = 0.2126 * $pixel.R + 0.7152 * $pixel.G + 0.0722 * $pixel.B
            if ($pixel.A -gt 48 -and $luma -lt 200) {
                for ($dy = -$outlineRadius; $dy -le $outlineRadius; $dy++) {
                    for ($dx = -$outlineRadius; $dx -le $outlineRadius; $dx++) {
                        if ($dx * $dx + $dy * $dy -gt $outlineRadius * $outlineRadius) { continue }
                        $outlineX = $x + $dx
                        $outlineY = $y + $dy
                        if ($outlineX -ge 0 -and $outlineX -lt $canvasSize -and $outlineY -ge 0 -and $outlineY -lt $canvasSize) {
                            $outlined.SetPixel($outlineX, $outlineY, [System.Drawing.Color]::FromArgb(255, 8, 7, 7))
                        }
                    }
                }
            }
        }
    }
    $outlineGraphics = [System.Drawing.Graphics]::FromImage($outlined)
    $outlineGraphics.DrawImageUnscaled($target, 0, 0)
    $outlineGraphics.Dispose()
    $outlined.Save((Join-Path $targetRoot ($state.Name + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    $outlined.Dispose()
    $target.Dispose()
    Write-Output ($state.Name + ': 256x256 source, hotspot ' + $state.HotspotX + ',' + $state.HotspotY + ', outline 5px, color 10% darker')
}
$sheet.Dispose()
