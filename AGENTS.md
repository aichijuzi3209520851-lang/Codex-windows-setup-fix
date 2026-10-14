# AGENTS.md — Instructions for AI coding agents

You are an AI assistant/agent. A human has opened this repository or pasted a prompt referencing it because they want the **Codex desktop "Windows setup didn't finish"** fix on their own computer. This file tells you exactly what to do — and what NOT to do. The procedure below is verified on a real machine; follow it as written instead of improvising.

**中文读者：** 本仓库是 Codex 桌面版「Windows 设置未完成」故障的一键修复工具；按下方步骤执行即可。

## What this repo fixes (context, 30 seconds)

- Codex desktop (OpenAI, MSIX package `OpenAI.Codex`, UI process `ChatGPT.exe`) shows the banner **"Windows setup didn't finish — Setup stopped"**; clicking *Retry setup* never works.
- Root cause: `codex-windows-sandbox-setup.exe` must exclusively lock `%USERPROFILE%\.codex\.sandbox-bin`, but the app's own auto-start service **`CodexSandboxService.OpenAI.Codex`** (display name "ChatGPT") holds that directory → provisioning always fails while the service runs.
- Fix = quit the app → stop the service → relaunch the app (setup then succeeds on its own) → start the service again. All of it is scripted in `scripts/`.

## Preconditions

- Windows 10/11; the Codex desktop app installed; this repo cloned with `scripts/` intact (`Fix-Codex-Setup.cmd`, `fix-codex-setup.ps1`, `fix-codex-setup.ico` must stay together).
- Stopping the service requires **administrator rights**: the user must approve one **UAC** prompt. Say so *before* you trigger anything; never claim the fix ran if UAC was declined.

## Task A — Install the fix to their desktop (deploy)

1. Verify the three files exist under `scripts/`.
2. From the repo root run:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-To-Desktop.ps1
   ```
3. Success = the script prints the green `[OK]` line. A `Fix-Codex-Setup` shortcut with a custom icon (blue tile + wrench + green check) now sits on the desktop.
4. If the script notes a raw `Fix-Codex-Setup.cmd` on the desktop, tell the user it can be deleted — the shortcut replaces it.
5. Tell the user: keep this repo folder where it is (the shortcut points into it) and see "How to use" below.

## Task B — Run the fix right now (user currently has the failure banner)

1. Explain what will happen: their Codex app will be closed (save work first), the service `CodexSandboxService.OpenAI.Codex` will be stopped and later restarted, and Codex will relaunch and finish setup within ~1–5 minutes.
2. Run either (both are equivalent):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fix-codex-setup.ps1
   ```
   or have the user double-click `scripts\Fix-Codex-Setup.cmd`. The script **self-elevates**: a UAC prompt will appear — ask the user to approve it.
3. Success = green `[DONE]` line in the console, plus these checks:
   - `%USERPROFILE%\.codex\.sandbox\setup_marker.json` is non-empty JSON;
   - `%USERPROFILE%\.codex\.sandbox\setup_error.json` is empty or gone;
   - the Codex banner turns green: "Windows setup is complete".
4. The script is **idempotent** — if setup state is already healthy it says so and changes nothing. Re-running it is always safe.

## Safety constraints (do not cross)

- Touch only: this repo's files, the OpenAI.Codex app's own processes (`ChatGPT.exe`, `codex.exe`, `codex-windows-sandbox-setup.exe`), and its own service `CodexSandboxService.OpenAI.Codex`.
- Never stop/uninstall/disable other services, never edit anything under `C:\Program Files\WindowsApps`, never run registry "cleanup", never disable the sandbox service permanently (the app needs it — the fix stops it only temporarily and starts it again).
- Do not refactor or "improve" this repo while deploying it; the procedure is verified as-is.
- If setup still fails **with the service stopped**, stop and gather a report instead of guessing: Windows build (`winver`), Codex desktop version, last ~30 lines of the newest `%USERPROFILE%\.codex\.sandbox\sandbox-*.log` — tell the user to redact their username/paths — and suggest opening an issue with the repo's template.

## Why the problem recurs (for your answer to the user)

The trigger lives inside OpenAI's app: whenever setup state goes stale (most often right after an app update) the app re-provisions while its service is running, and fails again. There is no permanent eradication from outside the app — the durable answer is: when the banner appears, run this tool once. Do not promise the user it will never come back.
