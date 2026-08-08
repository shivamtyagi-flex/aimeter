# AIMeter Adoption Improvements Design

## Goal

Make AIMeter installable and usable in under 2 minutes by any macOS developer using AI APIs. Three changes: Homebrew distribution, auto-start via LaunchAgent, and interactive tool auto-setup.

## Target User

Open-source: any macOS developer using AI APIs (Claude Code, Cursor, VS Code, OpenAI scripts). No Flex-specific assumptions.

---

## 1. Homebrew Formula

### Distribution

Homebrew tap at `smriti-memcore/homebrew-tap`. Users install with:

```bash
brew tap smriti-memcore/tap
brew install aimeter
```

### Build strategy

Pre-built universal binary (arm64 + x86_64) included in the GitHub release tarball. The formula does NOT compile Swift at install time — this avoids the Xcode CLI tools dependency and bottles issue. The GitHub Actions release workflow compiles the universal binary:

```bash
swiftc -O -o aimeter-arm64 -target arm64-apple-macosx12.0 MenuBarApp.swift
swiftc -O -o aimeter-x86_64 -target x86_64-apple-macosx12.0 MenuBarApp.swift
lipo -create -output aimeter aimeter-arm64 aimeter-x86_64
```

### What the formula does

- Downloads release tarball containing pre-built `aimeter` binary, `aimeter_daemon.py`, `aimeter_cli.py`, and web assets
- Installs all files to Homebrew prefix
- Includes a `service` block for `brew services` integration (see Section 2)
- Post-install caveats message: run `aimeter setup` to configure tools

### Uninstall

```bash
aimeter setup --undo        # remove tool configs first
brew services stop aimeter   # unload LaunchAgent
brew uninstall aimeter       # remove files
```

Caveats message on uninstall reminds user to run `aimeter setup --undo`.

### Files

- New repo: `smriti-memcore/homebrew-tap` containing `Formula/aimeter.rb`
- GitHub Actions workflow in `aimeter` repo to create tagged releases with universal binary tarballs

---

## 2. LaunchAgent

### Plist

`~/Library/LaunchAgents/com.aimeter.app.plist`

Integrated via Homebrew's `service` block in the formula — this is the standard mechanism for `brew services` to work. The formula declares the service; Homebrew manages the plist lifecycle.

### Behavior

- Starts the Swift `aimeter` binary on login
- The Swift app internally spawns the Python daemon via existing `DaemonManager` (no architecture change)
- `KeepAlive.SuccessfulExit: false` — launchd restarts only on crash (non-zero exit), NOT when user quits via menu. This avoids the surprise relaunch behavior.
- `RunAtLoad: true` — starts on install and every login
- Stdout/stderr to `~/.aimeter/aimeter.log`

### Lifecycle

```bash
brew services start aimeter    # enable + start
brew services stop aimeter     # stop + disable
brew services restart aimeter  # restart
```

### Install script change

`install.sh` (for non-Homebrew users) copies the plist and runs `launchctl bootstrap`. Prints instructions for `aimeter setup`.

---

## 3. Auto-Setup (`aimeter setup`)

### Implementation

New file: `aimeter_cli.py` — separate from the daemon. The Swift binary checks `CommandLine.arguments` before calling `NSApplication.shared.run()`. If args contain `setup`, it resolves `aimeter_cli.py` path (same directory resolution as `aimeter_daemon.py` at line 14-27 of MenuBarApp.swift) and calls `execv` to replace the process with `python3 aimeter_cli.py setup [args]`. This avoids initializing the GUI.

### How each tool is tracked

Important distinction: AIMeter tracks tools in two different ways:

1. **Proxy mode** (OpenAI, Cursor, VS Code, custom scripts) — API calls route through `http://127.0.0.1:5333`. Requires setting `*_BASE_URL` env vars.
2. **Log watcher mode** (Claude Code) — `ClaudeLogWatcher` reads `~/.claude/projects/` logs directly. No proxy needed, no env var changes.

Auto-setup configures each tool for the appropriate mode.

### Flow

```
$ aimeter setup

Scanning for AI tools...

  Found: Claude Code    log watcher (auto-tracked, no config needed)
  Found: Cursor         ~/Library/Application Support/Cursor/User/settings.json
  Skip:  VS Code        not found
  Found: Shell profile  ~/.zshrc

Claude Code is already tracked via log watching. No changes needed.

Configure Cursor? [Y/n] y
  Set http.proxy in Cursor settings.json

Add env vars to ~/.zshrc for CLI tools? [Y/n] y
  Added OPENAI_BASE_URL and ANTHROPIC_BASE_URL

Done! AIMeter is tracking your AI spend.
Dashboard: http://127.0.0.1:5333
```

### Detection and config per tool

| Tool | Detection | Tracking Mode | Config change |
|------|-----------|---------------|---------------|
| Claude Code | `~/.claude/` exists | Log watcher | None (inform user it's auto-tracked) |
| Cursor | `~/Library/Application Support/Cursor/` exists | Proxy | Add proxy to Cursor `settings.json` |
| VS Code | `~/Library/Application Support/Code/` exists | Proxy | Add proxy to VS Code `settings.json` |
| Shell (zsh/bash) | Check `$SHELL` | Proxy | Append export lines to rc file |

### Idempotency

Before appending to shell profiles, check if the exact export line already exists (grep). Skip with a message if found. Same for JSON config files — check if the key already exists and matches before writing.

### Reversibility

`aimeter setup --undo` removes all config changes. State file at `~/.aimeter/setup_state.json`:

```json
{
  "configured_at": "2026-08-07T14:30:00",
  "changes": [
    {"file": "~/.zshrc", "type": "append", "lines": ["export OPENAI_BASE_URL=...", "export ANTHROPIC_BASE_URL=..."]},
    {"file": "~/Library/Application Support/Cursor/User/settings.json", "type": "json_key", "key": "http.proxy", "previous_value": null}
  ]
}
```

`--undo` reads this file and reverses each change (remove appended lines, restore previous JSON values or delete keys).

### Conflict detection

If `ANTHROPIC_BASE_URL` or `OPENAI_BASE_URL` is already set to a non-aimeter value (e.g. Headroom proxy at `127.0.0.1:8787`), warn and skip unless `--force`.

---

## New/Changed Files

| File | Action | Purpose |
|------|--------|---------|
| `aimeter_cli.py` | New | Auto-setup CLI (`aimeter setup`, `aimeter setup --undo`) |
| `com.aimeter.app.plist` | New | LaunchAgent plist template (also used by Homebrew service block) |
| `install.sh` | Modify | Add LaunchAgent install + print setup instructions |
| `MenuBarApp.swift` | Modify | Add arg check before NSApplication.run(), delegate `setup` to CLI via execv |
| `.github/workflows/release.yml` | New | Build universal binary + create tagged release |
| Separate repo: `smriti-memcore/homebrew-tap/Formula/aimeter.rb` | New | Homebrew formula with service block |

## Out of Scope

- Linux support
- Windows support
- Team/shared dashboards
- Per-session cost tracking
- Cost alert notifications
- Tracking Claude Code via proxy (log watcher is the correct approach)
