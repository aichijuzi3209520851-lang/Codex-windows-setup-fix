# Codex Windows Setup Fix

[中文说明 →](README.zh-CN.md)

A diagnosis record and **one-click workaround** for the Codex desktop (OpenAI, Windows) bug where the first-run "Windows setup" always fails with **"Windows setup didn't finish — Setup stopped"**, and clicking **Retry setup** never helps.

> **Status:** community workaround, verified in **2026-10 on Windows 11** with **Codex desktop v26.1007.x** (MSIX package `OpenAI.Codex`). The root cause is inside the app itself: its sandbox setup helper conflicts with its own auto-start Windows service. This repo will be archived once OpenAI fixes it upstream — star/watch it if you want to know.

## Symptoms

The failure goes through three banner states inside the Codex desktop app:

| 1. Setup required | 2. Setting up (minutes…) | 3. Failure — loops forever |
|---|---|---|
| ![Finish Windows setup to continue](docs/images/symptom-1-setup-required.png) | ![Finishing Windows setup](docs/images/symptom-2-creating-sandbox.png) | ![Windows setup didn't finish](docs/images/symptom-3-setup-stopped.png) |

Characteristics that identify this bug:

- Stage 2 ("creating a sandbox…") spins for a few minutes, then stage 3 appears;
- **"Retry setup" always fails again** — the button cannot fix it;
- Rebooting the PC doesn't help either;
- It often starts right after the app has been updated.

## Why it happens

The Codex desktop app on Windows provisions a sandbox on first launch (and re-provisions whenever that state goes stale — typically after an app update). The provisioning helper `codex-windows-sandbox-setup.exe` needs an **exclusive lock on the directory** `C:\Users\<you>\.codex\.sandbox-bin`.

But the app ships its own Windows service — **`CodexSandboxService.OpenAI.Codex`** (display name *"ChatGPT"*, start type **Automatic**, running as `LocalSystem`) — and that service holds the directory open from the moment it starts at boot.

So whenever the app needs to (re)run setup while the service is running, the helper fails deterministically with:

```text
setup error: helper_sandbox_lock_failed: lock sandbox bin dir
\\?\C:\Users\<you>\.codex\.sandbox-bin failed: open directory
\\?\C:\Users\<you>\.codex\.sandbox-bin
```

The in-app **Retry setup** button only re-runs the helper — it never stops the service — so it can never succeed. This is the trap: *the fix requires stopping the very service the app auto-starts.*

## Fixes

### Option A — one-click script (recommended)

1. Download the [`scripts/`](scripts/) folder from this repo (keep both files together in the same folder);
2. Double-click **`Fix-Codex-Setup.cmd`**;
3. Approve the **UAC** prompt (administrator rights are needed to stop the service);
4. Wait for the green **`[DONE]`** line — typically 1–3 minutes:

![Tool run success](docs/images/tool-run-success.png)

What it does (all steps are idempotent — safe to run any time):

| Step | Action | Why |
|---|---|---|
| 1/4 | Quit Codex (`ChatGPT.exe`, `codex.exe`, stale setup helpers) | The app must restart for setup to re-run |
| 2/4 | `Stop-Service CodexSandboxService.OpenAI.Codex` | Releases the `sandbox-bin` directory lock |
| 3/4 | Relaunch the app and poll for up to 5 min | Setup now succeeds on its own; the tool watches `setup_marker.json` / `setup_error.json` |
| 4/4 | `Start-Service` the sandbox service again | Restores normal sandbox operation |

If your setup state is already healthy, the tool detects that ("无需重新初始化") and exits without changing anything.

> Prefer not to run random scripts? Use **Option B** — it is the exact same sequence, by hand.

### Option B — manual steps

```powershell
# 1. Quit the app completely: right-click its taskbar icon -> Exit,
#    or end "ChatGPT.exe" / "codex.exe" processes in Task Manager.

# 2. In an ELEVATED (Administrator) PowerShell:
Stop-Service CodexSandboxService.OpenAI.Codex -Force

# 3. Start the app again from the Start menu.
#    Setup runs by itself and completes within seconds — no need to click Retry.

# 4. Verify (see next section), then restore the service:
Start-Service CodexSandboxService.OpenAI.Codex
```

## How to verify it worked

- The app shows the green banner: **"Windows setup is complete — ChatGPT can now create files, edit code, and take actions"**

  ![Windows setup is complete](docs/images/success-banner.png)

- On disk, all three files agree:

| File | Before (broken) | After (fixed) |
|---|---|---|
| `~\.codex\.sandbox\setup_marker.json` | 0 bytes | non-empty JSON, e.g. `{"version": 5, ...}` |
| `~\.codex\.sandbox\setup_error.json` | contains the `helper_sandbox_lock_failed` error | empty / cleared |
| `~\.codex\.sandbox\sandbox-*.log` (newest) | ends with `setup error: helper_sandbox_lock_failed` | no error tail |

Example success marker (`setup_marker.json`):

```json
{
  "version": 5,
  "offline_username": "CodexSandboxOffline",
  "online_username": "CodexSandboxOnline",
  "created_at": "2026-10-14T03:10:55.939412+00:00",
  "proxy_ports": [],
  "allow_local_binding": false,
  "read_roots": [],
  "write_roots": []
}
```

## Technical deep dive

### Evidence: the service is the lock holder

Controlled A/B on one machine (Windows 11, Codex v26.1007.x, 2026-10-14):

| Time | Sandbox service state | Action | Result |
|---|---|---|---|
| 08:36 | RUNNING (auto-started at boot) | App auto-started at logon, provisioning triggered | guard file created, then failed |
| 10:49 | RUNNING | User clicked **Retry setup** | ❌ `helper_sandbox_lock_failed` |
| 11:03 | RUNNING | User clicked **Retry setup** again | ❌ `helper_sandbox_lock_failed` |
| 11:10 | **STOPPED** | App relaunched | ✅ setup completed in seconds, marker written |
| 11:14 | RUNNING (manually restored) | — | normal operation |
| 12:18 | cycled by the tool | End-to-end run of this repo's script | ✅ passed |

Same machine, same app version — the only variable that changes the outcome is whether the service is running.

### Where everything lives

| Item | Location |
|---|---|
| App package (MSIX) | `OpenAI.Codex` — UI process is `ChatGPT.exe`, launch AUMID `OpenAI.Codex_2p2nqsd0c76g0!App` |
| Sandbox service | `CodexSandboxService.OpenAI.Codex`, display name *"ChatGPT"*, `StartType=Auto`, binary `codex-windows-sandbox-service.exe` inside the package |
| Setup helper | `codex-windows-sandbox-setup.exe` (spawned during provisioning) |
| State dir | `%USERPROFILE%\.codex\` — `.sandbox\` holds `setup_marker.json`, `setup_error.json`, `sandbox-*.log` |
| Lock-contended dir | `%USERPROFILE%\.codex\.sandbox-bin` |
| Provisioning guard | `%USERPROFILE%\.codex\.codex-provisioning-<id>.guard` |

### Related quirk: why it starts at every boot

The same MSIX package declares a startup task in its manifest:

```xml
<uap5:Extension Category="windows.startupTask" Executable="app/ChatGPT.exe" ...>
  <uap5:StartupTask TaskId="App" Enabled="true" DisplayName="ChatGPT" />
```

So **the app auto-starts at logon under the display name "ChatGPT"** (Task Manager → Startup apps), *not* "Codex" — easy to miss. Combined with the auto-start service, this is why the failure greets you right after boot on the day an update lands. If you don't want the app at boot, disable that entry; it does not affect this fix.

## FAQ

**Q: Why does "Retry setup" never work?**
It re-runs the failing helper but never releases the lock — the service keeps running in the background. You must stop the service first (this repo's script or Option B).

**Q: Will the problem come back?**
Probably yes, the next time your setup state goes stale (most often after a Codex desktop update re-provisions the sandbox). Keep this repo around and re-run the tool — it is idempotent.

**Q: Is the script safe? What does it touch?**
Only OpenAI.Codex's own things: it kills `ChatGPT.exe` / `codex.exe` / `codex-windows-sandbox-setup.exe` processes, stops and starts **only** its own service `CodexSandboxService.OpenAI.Codex`, and reads/deletes its own `setup_error.json`. It touches nothing else on your system. Full source is in [`scripts/fix-codex-setup.ps1`](scripts/fix-codex-setup.ps1) (~80 readable lines).

**Q: My setup failed again even with the service stopped.**
Please open an issue with your Windows build, Codex version, and the tail of the newest `sandbox-*.log` (see below). Different machines may have a different lock holder (e.g. antivirus) — the log names the failing step.

## Reporting your experience

Issues are welcome and useful — they help confirm how widespread this is and whether other Windows builds behave differently. When filing, please include:

- Windows version (`winver`) and Codex desktop version (MSIX package `OpenAI.Codex` version);
- Which banner stage you see, and whether you used the script or manual steps;
- The last ~30 lines of the newest `~\.codex\.sandbox\sandbox-*.log` and the contents of `setup_error.json` — **please redact your username/paths first**.

## Disclaimer & License

Use at your own risk. The script only operates the OpenAI.Codex app's own processes and its own Windows service, and the procedure was verified on one machine (details above); results on other configurations are not guaranteed. Not affiliated with or endorsed by OpenAI. Please also report the bug to OpenAI so it can be fixed upstream — that is the real cure.

Released under the [MIT License](LICENSE).
