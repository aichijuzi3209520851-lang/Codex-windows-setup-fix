@echo off
rem ============================================================================
rem  Fix-Codex-Setup - one-click fix for the Codex desktop banner
rem  "Windows setup didn't finish / Setup stopped" (helper_sandbox_lock_failed)
rem
rem  Usage: keep this file together with fix-codex-setup.ps1 (same folder),
rem  double-click, approve the UAC prompt, wait for the green [DONE] line.
rem  The PowerShell script does all the work and prints bilingual status.
rem  Safe to re-run; MIT License; see README.md for details.
rem ============================================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-codex-setup.ps1"
if %errorlevel% neq 0 pause
