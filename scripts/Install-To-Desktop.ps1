<#
.SYNOPSIS
  Creates a desktop shortcut for Fix-Codex-Setup.cmd with its custom icon.

.DESCRIPTION
  Run this once after cloning the repo (keep the repo folder in place afterwards,
  the shortcut points into it). It creates:

    <Desktop>\Fix-Codex-Setup.lnk  ->  <this scripts folder>\Fix-Codex-Setup.cmd
                                        icon: fix-codex-setup.ico

  If a raw Fix-Codex-Setup.cmd already sits directly on your desktop, you can
  delete that file afterwards - the shortcut replaces it.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-To-Desktop.ps1
#>
[CmdletBinding()]
param(
    [string]$SourceDir,
    [string]$DesktopPath
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot is not populated during param-default evaluation; fall back to $PSCommandPath
if([string]::IsNullOrEmpty($SourceDir)){ $SourceDir = Split-Path -Parent $PSCommandPath }
if([string]::IsNullOrEmpty($DesktopPath)){ $DesktopPath = [Environment]::GetFolderPath('Desktop') }

$cmd      = Join-Path $SourceDir 'Fix-Codex-Setup.cmd'
$ps1      = Join-Path $SourceDir 'fix-codex-setup.ps1'
$ico      = Join-Path $SourceDir 'fix-codex-setup.ico'
$lnkPath  = Join-Path $DesktopPath 'Fix-Codex-Setup.lnk'

foreach($f in @($cmd, $ps1, $ico)){
    if(-not (Test-Path $f)){
        throw "Missing file: $f`nRun this script from the repo's scripts folder (all three files must stay together). / 缺少文件：请在仓库 scripts 目录下运行，三个文件必须在同一目录。"
    }
}

$ws  = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath       = $cmd
$lnk.WorkingDirectory = $SourceDir
$lnk.IconLocation     = "$ico,0"
$lnk.Description      = "Fix Codex desktop ""Windows setup didn't finish"" (one-click)"
$lnk.Save()

# ask Explorer to refresh its icon cache for the new shortcut
ie4uinit.exe -show | Out-Null

# verify what was actually written
$check = $ws.CreateShortcut($lnkPath)
if($check.TargetPath -ne $cmd -or $check.IconLocation -notlike "$ico*"){
    throw 'Shortcut verification failed / 快捷方式校验失败'
}

$rawCmd = Join-Path $DesktopPath 'Fix-Codex-Setup.cmd'
if(Test-Path $rawCmd){
    Write-Host "[Note] A raw Fix-Codex-Setup.cmd also exists on your desktop - you can delete it, the shortcut replaces it." -ForegroundColor Yellow
    Write-Host "[提示] 桌面上还有一个原始的 Fix-Codex-Setup.cmd，可以删除它，用快捷方式代替。" -ForegroundColor Yellow
}

Write-Host "[OK] Desktop shortcut created: $lnkPath" -ForegroundColor Green
Write-Host "[OK] 桌面快捷方式已创建（带图标），保持本仓库文件夹位置不变即可。" -ForegroundColor Green
