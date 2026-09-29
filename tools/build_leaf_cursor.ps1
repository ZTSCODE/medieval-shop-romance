Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $projectRoot 'outputs/cursor-leaf-set-20260919'
$targetRoot = Join-Path $projectRoot 'assets/art/ui/leaf_cursor'
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
$states = @(
    @{ Name = 'normal'; TipX = 203; TipY = 211; TailY = 1120 },
    @{ Name = 'hover'; TipX = 157; TipY = 112; TailY = 1155 },
    @{ Name = 'pressed'; TipX = 201; TipY = 211; TailY = 1121 }
)
foreach ($state in $states) {
    $source = [System.Drawing.Bitmap]::new((Join-Path $sourceRoot ($state.Name + '.png')))
    $target = [System.Drawing.Bitmap]::new(56, 56, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($target)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $factor = 43.0 / ($state.TailY - $state.TipY)
    $rect = [System.Drawing.RectangleF]::new((6 - $state.TipX * $factor), (6 - $state.TipY * $factor), ($source.Width * $factor), ($source.Height * $factor))
    $graphics.DrawImage($source, $rect)
    $target.Save((Join-Path $targetRoot ($state.Name + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $target.Dispose()
    $source.Dispose()
    Write-Output ($state.Name + ': 56x56, hotspot 6,6')
}
