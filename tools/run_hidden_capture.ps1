# 在后台运行需要真实渲染的截图脚本：窗口隐藏且放在屏幕外，不打扰正在使用电脑的人。
# Godot 的 --headless 不渲染画面、无法截图，所以这里用隐藏窗口代替。
# 用法：pwsh -File tools/run_hidden_capture.ps1 tests/opening_story_capture.gd [-- 其他参数]
param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$Godot = "C:\Users\ZTCUS\Desktop\Godot.exe",
    [int]$TimeoutSeconds = 600,
    [string[]]$ExtraArgs = @("--flow-qa")
)
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP ("godot-capture-" + [IO.Path]::GetFileNameWithoutExtension($Script) + ".log")
$err = "$out.err"
$arguments = @("--path", "`"$project`"", "--position", "-32000,-32000", "--script", $Script, "--") + $ExtraArgs
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    $process.Kill()
    Write-Output "TIMEOUT after $TimeoutSeconds s"
    exit 2
}
Get-Content $out | Where-Object { $_ -match "PASS|FAIL|failures|SCRIPT ERROR" }
exit $process.ExitCode
