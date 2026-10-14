<#
.SYNOPSIS
  One-click fix for the Codex desktop "Windows setup didn't finish" banner
  (error: helper_sandbox_lock_failed).

.DESCRIPTION
  Root cause: the sandbox setup helper (codex-windows-sandbox-setup.exe) needs
  an exclusive lock on ~\.codex\.sandbox-bin, but the app's own auto-start
  Windows service (CodexSandboxService.OpenAI.Codex) holds that directory open
  while running. So whenever setup state goes stale (typically after an app
  update), provisioning always fails and the in-app "Retry setup" button can
  never succeed.

  This script performs the proven 4-step fix:
    1. Quit the Codex app (ChatGPT.exe / codex.exe / stale setup helpers)
    2. Stop CodexSandboxService.OpenAI.Codex  -> releases the directory lock
    3. Relaunch the app and wait (up to 5 min) for setup to finish by itself
    4. Start the service again

  Idempotent and safe to re-run: it only touches OpenAI.Codex's own processes
  and its own Windows service. If setup state is already healthy it detects
  that and exits without changing anything.

.EXAMPLE
  Double-click Fix-Codex-Setup.cmd, approve the UAC prompt, wait for the
  green "[DONE]" line.

.NOTES
  Verified 2026-10 on Windows 11 with Codex desktop v26.1007.x (MSIX package
  OpenAI.Codex). MIT License. Not affiliated with OpenAI.
#>

$ErrorActionPreference = 'SilentlyContinue'

$svc     = 'CodexSandboxService.OpenAI.Codex'
$sb      = Join-Path $env:USERPROFILE '.codex\.sandbox'
$marker  = Join-Path $sb 'setup_marker.json'
$errFile = Join-Path $sb 'setup_error.json'
$aumid   = 'OpenAI.Codex_2p2nqsd0c76g0!App'

function Pause-Exit($code) { Read-Host 'Press Enter to exit / 按回车键退出'; exit $code }
function Fail($msg) { Write-Host ''; Write-Host "[FAIL / 失败] $msg" -ForegroundColor Red; Pause-Exit 1 }

# --- Self-elevation: stopping the LocalSystem sandbox service needs admin ---
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Requesting admin privileges (please click "Yes" on the UAC prompt) / 正在请求管理员权限（请在 UAC 弹窗中点“是”）...'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"" `
            -ErrorAction Stop
        exit 0
    }
    catch {
        Write-Host 'UAC was cancelled. Right-click Fix-Codex-Setup.cmd and choose "Run as administrator".' -ForegroundColor Red
        Write-Host 'UAC 已取消。请右键 Fix-Codex-Setup.cmd，选择“以管理员身份运行”。' -ForegroundColor Red
        Pause-Exit 1
    }
}

Write-Host '[1/4] Quitting Codex (save any work in progress first) / 正在退出 Codex（请先保存正在进行的对话）...'
Get-Process ChatGPT, codex, codex-windows-sandbox-setup -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2

Write-Host '[2/4] Stopping the sandbox service (releasing the directory lock) / 正在停止沙箱服务（释放目录锁）...'
Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Service $svc).Status -ne 'Stopped' -and (Get-Date) -lt $deadline) { Start-Sleep 1 }
if ((Get-Service $svc).Status -ne 'Stopped') { Fail "Sandbox service will not stop, current status: $((Get-Service $svc).Status)`n沙箱服务无法停止，当前状态同上。" }
Get-Process codex-windows-sandbox-setup -ErrorAction SilentlyContinue | Stop-Process -Force

$markerT0 = if (Test-Path $marker) { (Get-Item $marker).LastWriteTime } else { [DateTime]::MinValue }
Remove-Item $errFile -Force -ErrorAction SilentlyContinue

Write-Host '[3/4] Relaunching Codex and waiting for setup (up to 5 min; please do not touch the Codex window) / 正在启动 Codex 并等待自动设置（最长 5 分钟，期间请勿操作 Codex 窗口）...'
Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$aumid"
$start    = Get-Date
$deadline = $start.AddMinutes(5)
$ok       = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep 2
    if ((Test-Path $errFile) -and (Get-Item $errFile).Length -gt 0) {
        Fail ("Setup failed again:`n" + (Get-Content $errFile -Raw) + "`nLogs: newest sandbox-*.log under $sb`n设置再次失败，排查日志：$sb 下最新的 sandbox-*.log")
    }
    if ((Test-Path $marker) -and (Get-Item $marker).LastWriteTime -gt $markerT0) {
        Write-Host '  Fresh setup_marker.json detected -> provisioning succeeded. / 检测到新的设置完成标记，初始化成功。' -ForegroundColor Green
        $ok = $true
        break
    }
    if (((Get-Date) - $start).TotalSeconds -gt 90 -and
        -not (Get-Process codex-windows-sandbox-setup -ErrorAction SilentlyContinue) -and
        (Test-Path $marker) -and (Get-Item $marker).Length -gt 0) {
        Write-Host '  Setup state is already healthy, nothing to re-provision. / 当前状态本来就正常，无需重新初始化。' -ForegroundColor Green
        $ok = $true
        break
    }
}
if (-not $ok) { Fail 'Timed out after 5 minutes - please screenshot the Codex window banner and open an issue.`n等待超时（5 分钟）：请截图 Codex 窗口的横幅状态并开 issue 反馈。' }

Write-Host '[4/4] Starting the sandbox service again / 正在恢复沙箱服务...'
Start-Service -Name $svc -ErrorAction Stop
Write-Host ''
Write-Host '[DONE] Fixed: setup is complete and the sandbox service is running again. / [完成] 修复完成：设置已就绪，沙箱服务已启动，Codex 可以正常使用了。' -ForegroundColor Green
Pause-Exit 0
