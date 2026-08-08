# AIMeter Adoption Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AIMeter installable via `brew install` with auto-start on login and interactive `aimeter setup` for tool configuration.

**Architecture:** Three independent features layered bottom-up: LaunchAgent plist (no code deps), auto-setup CLI (new `aimeter_cli.py`), and Homebrew formula (packages everything). The Swift binary gains a pre-`NSApplication` arg check that delegates `setup` to the Python CLI via `execv`.

**Tech Stack:** Swift 5+, Python 3.9+, Homebrew Ruby DSL, GitHub Actions, launchctl

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `com.aimeter.app.plist` | Create | LaunchAgent template |
| `aimeter_cli.py` | Create | Auto-setup CLI (`aimeter setup`, `--undo`) |
| `MenuBarApp.swift` | Modify | Add arg parsing before NSApplication.run() to delegate `setup` |
| `install.sh` | Modify | Add LaunchAgent install + setup instructions |
| `.github/workflows/release.yml` | Create | Build universal binary + create GitHub release |
| `.gitignore` | Modify | Add `aimeter-arm64`, `aimeter-x86_64` build artifacts |
| `tests/test_cli.py` | Create | Tests for auto-setup CLI |

The Homebrew formula (`Formula/aimeter.rb`) lives in a separate repo `smriti-memcore/homebrew-tap` — Task 5 creates it.

---

### Task 1: LaunchAgent Plist

**Files:**
- Create: `com.aimeter.app.plist`

- [ ] **Step 1: Create the plist file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aimeter.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>__AIMETER_BIN__</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>__HOME__/.aimeter/aimeter.log</string>
    <key>StandardErrorPath</key>
    <string>__HOME__/.aimeter/aimeter.log</string>
</dict>
</plist>
```

Note: `__AIMETER_BIN__` and `__HOME__` are placeholders replaced by `install.sh` during install.

- [ ] **Step 2: Verify plist syntax**

Run: `plutil -lint com.aimeter.app.plist`
Expected: `com.aimeter.app.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add com.aimeter.app.plist
git commit -m "feat: add LaunchAgent plist for auto-start on login"
```

---

### Task 2: Update install.sh

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Update install.sh to install LaunchAgent and print setup instructions**

Replace the current `install.sh` with:

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.aimeter/bin"
PLIST_NAME="com.aimeter.app"
PLIST_SRC="$SCRIPT_DIR/com.aimeter.app.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "=== AIMeter Installer ==="

# 1. Compile Swift binary
echo "Compiling AIMeter for $(uname -m)..."
swiftc -O -o "$SCRIPT_DIR/aimeter" "$SCRIPT_DIR/MenuBarApp.swift" \
    -framework AppKit -framework Foundation
echo "  Compiled successfully."

# 2. Create install directory and copy files
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/aimeter" "$INSTALL_DIR/aimeter"
cp "$SCRIPT_DIR/aimeter_daemon.py" "$INSTALL_DIR/aimeter_daemon.py"
cp "$SCRIPT_DIR/aimeter_cli.py" "$INSTALL_DIR/aimeter_cli.py"
cp "$SCRIPT_DIR/index.html" "$INSTALL_DIR/index.html"
cp "$SCRIPT_DIR/index.css" "$INSTALL_DIR/index.css"
cp "$SCRIPT_DIR/dashboard.js" "$INSTALL_DIR/dashboard.js"

# 3. Install LaunchAgent
echo "Installing LaunchAgent..."
mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$HOME/.aimeter"
sed -e "s|__AIMETER_BIN__|$INSTALL_DIR/aimeter|g" \
    -e "s|__HOME__|$HOME|g" \
    "$PLIST_SRC" > "$PLIST_DST"

# Unload if already loaded, ignore errors
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
echo "  LaunchAgent installed and started."

# 4. Print next steps
echo ""
echo "=== AIMeter installed! ==="
echo ""
echo "  Menu bar icon should appear shortly."
echo "  Dashboard: http://127.0.0.1:5333"
echo ""
echo "  Next: run 'aimeter setup' to configure your AI tools."
echo "  (You may need to add $INSTALL_DIR to your PATH)"
echo ""
```

- [ ] **Step 2: Test the install script logic manually**

Run: `bash -n install.sh`
Expected: No syntax errors

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: install.sh installs LaunchAgent and prints setup instructions"
```

---

### Task 3: Auto-Setup CLI (`aimeter_cli.py`)

**Files:**
- Create: `aimeter_cli.py`
- Create: `tests/test_cli.py`

- [ ] **Step 1: Write tests for the setup CLI**

Create `tests/test_cli.py`:

```python
import json
import os
import tempfile
import unittest
from unittest.mock import patch

import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from aimeter_cli import (
    detect_tools,
    configure_shell_profile,
    configure_cursor,
    configure_claude_code,
    read_setup_state,
    write_setup_state,
)

PROXY_URL = "http://127.0.0.1:5333"


class TestDetectTools(unittest.TestCase):
    def test_detects_claude_code(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            claude_dir = os.path.join(tmpdir, ".claude")
            os.makedirs(claude_dir)
            with patch("aimeter_cli.HOME", tmpdir):
                tools = detect_tools()
        claude = [t for t in tools if t["name"] == "Claude Code"]
        self.assertEqual(len(claude), 1)
        self.assertEqual(claude[0]["mode"], "log_watcher")

    def test_detects_shell_profile_zsh(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            zshrc = os.path.join(tmpdir, ".zshrc")
            open(zshrc, "w").close()
            with patch("aimeter_cli.HOME", tmpdir), \
                 patch.dict(os.environ, {"SHELL": "/bin/zsh"}):
                tools = detect_tools()
        shell = [t for t in tools if t["name"] == "Shell profile"]
        self.assertEqual(len(shell), 1)


class TestConfigureShellProfile(unittest.TestCase):
    def test_appends_export_lines(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".zshrc", delete=False) as f:
            f.write("# existing content\n")
            path = f.name
        try:
            changes = configure_shell_profile(path)
            with open(path) as f:
                content = f.read()
            self.assertIn("OPENAI_BASE_URL", content)
            self.assertIn("ANTHROPIC_BASE_URL", content)
            self.assertEqual(len(changes), 1)
        finally:
            os.unlink(path)

    def test_idempotent(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".zshrc", delete=False) as f:
            f.write(f'export OPENAI_BASE_URL="{PROXY_URL}/openai/v1"\n')
            f.write(f'export ANTHROPIC_BASE_URL="{PROXY_URL}/anthropic"\n')
            path = f.name
        try:
            changes = configure_shell_profile(path)
            self.assertEqual(len(changes), 0)
        finally:
            os.unlink(path)


class TestConfigureCursor(unittest.TestCase):
    def test_sets_proxy_in_new_settings(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_path = os.path.join(tmpdir, "settings.json")
            with open(settings_path, "w") as f:
                json.dump({}, f)
            changes = configure_cursor(settings_path)
            with open(settings_path) as f:
                data = json.load(f)
            self.assertIn("http.proxy", data)
            self.assertEqual(len(changes), 1)


class TestConfigureClaudeCode(unittest.TestCase):
    def test_returns_no_changes(self):
        changes = configure_claude_code()
        self.assertEqual(len(changes), 0)


class TestConfigureVSCode(unittest.TestCase):
    def test_sets_proxy_in_new_settings(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_path = os.path.join(tmpdir, "settings.json")
            with open(settings_path, "w") as f:
                json.dump({}, f)
            changes = configure_json_settings(settings_path, "http.proxy", PROXY_URL)
            with open(settings_path) as f:
                data = json.load(f)
            self.assertIn("http.proxy", data)
            self.assertEqual(len(changes), 1)


class TestCheckConflicts(unittest.TestCase):
    def test_detects_existing_non_aimeter_url(self):
        with patch.dict(os.environ, {"ANTHROPIC_BASE_URL": "http://127.0.0.1:8787"}):
            conflicts = check_conflicts()
        self.assertEqual(len(conflicts), 1)
        self.assertEqual(conflicts[0][0], "ANTHROPIC_BASE_URL")

    def test_no_conflict_when_aimeter_url(self):
        with patch.dict(os.environ, {"ANTHROPIC_BASE_URL": f"{PROXY_URL}/anthropic"}):
            conflicts = check_conflicts()
        self.assertEqual(len(conflicts), 0)

    def test_no_conflict_when_unset(self):
        env = os.environ.copy()
        env.pop("ANTHROPIC_BASE_URL", None)
        env.pop("OPENAI_BASE_URL", None)
        with patch.dict(os.environ, env, clear=True):
            conflicts = check_conflicts()
        self.assertEqual(len(conflicts), 0)


class TestUndo(unittest.TestCase):
    def test_undo_removes_appended_lines(self):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".zshrc", delete=False) as f:
            f.write("# existing\n")
            path = f.name
        try:
            changes = configure_shell_profile(path)
            self.assertTrue(len(changes) > 0)

            state = {"changes": changes}
            with tempfile.TemporaryDirectory() as tmpdir:
                state_path = os.path.join(tmpdir, "setup_state.json")
                write_setup_state(state, state_path)

                from aimeter_cli import run_undo as _run_undo
                with patch("aimeter_cli.STATE_PATH", state_path):
                    _run_undo()

            with open(path) as f:
                content = f.read()
            self.assertNotIn("OPENAI_BASE_URL", content)
        finally:
            os.unlink(path)


class TestSetupState(unittest.TestCase):
    def test_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = os.path.join(tmpdir, "setup_state.json")
            state = {"changes": [{"file": "~/.zshrc", "type": "append"}]}
            write_setup_state(state, state_path)
            loaded = read_setup_state(state_path)
            self.assertEqual(loaded["changes"][0]["file"], "~/.zshrc")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/test_cli.py -v`
Expected: FAIL — `aimeter_cli` module not found

- [ ] **Step 3: Implement `aimeter_cli.py`**

Create `aimeter_cli.py`:

```python
#!/usr/bin/env python3
"""AIMeter auto-setup CLI. Detects AI tools and configures them to route through the AIMeter proxy."""

import json
import os
import sys
from datetime import datetime

HOME = os.path.expanduser("~")
PROXY_HOST = "http://127.0.0.1:5333"
STATE_DIR = os.path.join(HOME, ".aimeter")
STATE_PATH = os.path.join(STATE_DIR, "setup_state.json")

OPENAI_EXPORT = f'export OPENAI_BASE_URL="{PROXY_HOST}/openai/v1"'
ANTHROPIC_EXPORT = f'export ANTHROPIC_BASE_URL="{PROXY_HOST}/anthropic"'
AIMETER_MARKER = "# Added by aimeter setup"


def detect_tools():
    tools = []

    # Claude Code — tracked via log watcher, no proxy config needed
    if os.path.isdir(os.path.join(HOME, ".claude")):
        tools.append({
            "name": "Claude Code",
            "mode": "log_watcher",
            "config_path": None,
            "status": "auto-tracked via log watcher",
        })

    # Cursor
    cursor_settings = os.path.join(
        HOME, "Library", "Application Support", "Cursor", "User", "settings.json"
    )
    cursor_dir = os.path.dirname(cursor_settings)
    if os.path.isdir(cursor_dir):
        tools.append({
            "name": "Cursor",
            "mode": "proxy",
            "config_path": cursor_settings,
            "status": "found",
        })

    # VS Code
    vscode_settings = os.path.join(
        HOME, "Library", "Application Support", "Code", "User", "settings.json"
    )
    vscode_dir = os.path.dirname(vscode_settings)
    if os.path.isdir(vscode_dir):
        tools.append({
            "name": "VS Code",
            "mode": "proxy",
            "config_path": vscode_settings,
            "status": "found",
        })

    # Shell profile
    shell = os.environ.get("SHELL", "/bin/zsh")
    if "zsh" in shell:
        rc_path = os.path.join(HOME, ".zshrc")
    else:
        rc_path = os.path.join(HOME, ".bashrc")

    if os.path.isfile(rc_path):
        tools.append({
            "name": "Shell profile",
            "mode": "proxy",
            "config_path": rc_path,
            "status": "found",
        })

    return tools


def configure_shell_profile(rc_path):
    with open(rc_path) as f:
        content = f.read()

    if PROXY_HOST in content:
        return []

    lines = f"\n{AIMETER_MARKER}\n{OPENAI_EXPORT}\n{ANTHROPIC_EXPORT}\n"
    with open(rc_path, "a") as f:
        f.write(lines)

    return [{"file": rc_path, "type": "append", "lines": lines}]


def configure_json_settings(settings_path, key, value):
    if os.path.isfile(settings_path):
        with open(settings_path) as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                data = {}
    else:
        data = {}

    if data.get(key) == value:
        return []

    previous = data.get(key)
    data[key] = value

    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2)

    return [{"file": settings_path, "type": "json_key", "key": key, "value": value, "previous_value": previous}]


def configure_cursor(settings_path):
    return configure_json_settings(settings_path, "http.proxy", PROXY_HOST)


def configure_claude_code():
    return []


def check_conflicts():
    conflicts = []
    for var in ("OPENAI_BASE_URL", "ANTHROPIC_BASE_URL"):
        val = os.environ.get(var, "")
        if val and PROXY_HOST not in val:
            conflicts.append((var, val))
    return conflicts


def read_setup_state(path=None):
    path = path or STATE_PATH
    if not os.path.isfile(path):
        return {"changes": []}
    with open(path) as f:
        return json.load(f)


def write_setup_state(state, path=None):
    path = path or STATE_PATH
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(state, f, indent=2)


def prompt_yn(message, default=True):
    suffix = "[Y/n]" if default else "[y/N]"
    try:
        answer = input(f"{message} {suffix} ").strip().lower()
    except EOFError:
        return default
    if not answer:
        return default
    return answer in ("y", "yes")


def run_setup(force=False):
    print("\nScanning for AI tools...\n")
    tools = detect_tools()

    if not tools:
        print("  No AI tools detected.\n")
        return

    for tool in tools:
        if tool["mode"] == "log_watcher":
            print(f"  Found: {tool['name']:15s} {tool['status']}")
        elif tool["status"] == "found":
            print(f"  Found: {tool['name']:15s} {tool['config_path']}")
        else:
            print(f"  Skip:  {tool['name']:15s} {tool['status']}")

    # Check for conflicts
    if not force:
        conflicts = check_conflicts()
        for var, val in conflicts:
            print(f"\n  Warning: {var} is already set to {val}")
            print(f"           Use --force to override.")

    print()

    all_changes = []

    for tool in tools:
        if tool["mode"] == "log_watcher":
            print(f"  {tool['name']} is already tracked via log watching. No changes needed.")
            continue

        if tool["name"] == "Shell profile":
            # Check conflict
            if not force and any(v for v, _ in check_conflicts()):
                print(f"  Skipping {tool['name']} — env vars already set to non-aimeter values.")
                continue
            if prompt_yn(f"  Add env vars to {tool['config_path']}?"):
                changes = configure_shell_profile(tool["config_path"])
                if changes:
                    print(f"    Added OPENAI_BASE_URL and ANTHROPIC_BASE_URL")
                    all_changes.extend(changes)
                else:
                    print(f"    Already configured, skipping.")

        elif tool["name"] == "Cursor":
            if prompt_yn(f"  Configure {tool['name']}?"):
                changes = configure_cursor(tool["config_path"])
                if changes:
                    print(f"    Set http.proxy in {tool['config_path']}")
                    all_changes.extend(changes)
                else:
                    print(f"    Already configured, skipping.")

        elif tool["name"] == "VS Code":
            if prompt_yn(f"  Configure {tool['name']}?"):
                changes = configure_json_settings(
                    tool["config_path"], "http.proxy", PROXY_HOST
                )
                if changes:
                    print(f"    Set http.proxy in {tool['config_path']}")
                    all_changes.extend(changes)
                else:
                    print(f"    Already configured, skipping.")

    if all_changes:
        state = read_setup_state()
        state["configured_at"] = datetime.now().isoformat()
        state.setdefault("changes", []).extend(all_changes)
        write_setup_state(state)

    print(f"\nDone! Dashboard: http://127.0.0.1:5333\n")


def run_undo():
    state = read_setup_state()
    changes = state.get("changes", [])

    if not changes:
        print("No setup changes to undo.")
        return

    for change in reversed(changes):
        filepath = change["file"]
        if change["type"] == "append":
            lines_to_remove = change["lines"]
            if os.path.isfile(filepath):
                with open(filepath) as f:
                    content = f.read()
                content = content.replace(lines_to_remove, "")
                with open(filepath, "w") as f:
                    f.write(content)
                print(f"  Removed aimeter lines from {filepath}")

        elif change["type"] == "json_key":
            if os.path.isfile(filepath):
                with open(filepath) as f:
                    data = json.load(f)
                if change["previous_value"] is None:
                    data.pop(change["key"], None)
                else:
                    data[change["key"]] = change["previous_value"]
                with open(filepath, "w") as f:
                    json.dump(data, f, indent=2)
                print(f"  Restored {change['key']} in {filepath}")

    state["changes"] = []
    state["undone_at"] = datetime.now().isoformat()
    write_setup_state(state)
    print("\nAll setup changes reverted.")


def main():
    args = sys.argv[1:]

    if not args or args[0] == "setup":
        force = "--force" in args
        if "--undo" in args:
            run_undo()
        else:
            run_setup(force=force)
    else:
        print(f"Unknown command: {args[0]}")
        print("Usage: aimeter setup [--undo] [--force]")
        sys.exit(1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/test_cli.py -v`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add aimeter_cli.py tests/test_cli.py
git commit -m "feat: add auto-setup CLI with detect-and-prompt flow"
```

---

### Task 4: Swift Binary Arg Delegation

**Files:**
- Modify: `MenuBarApp.swift` (lines 347-351, the entry point where `NSApplication.shared.run()` is called)

- [ ] **Step 1: Add arg check before NSApplication initialization**

At the top of the entry point (before `NSApplication.shared.run()` is called), add:

```swift
// Check for CLI subcommands before starting GUI
let args = CommandLine.arguments
if args.count > 1 && args[1] == "setup" {
    let exeURL = URL(fileURLWithPath: args[0])
    let exeDir = exeURL.deletingLastPathComponent()
    let cliPath = exeDir.appendingPathComponent("aimeter_cli.py").path
    
    if FileManager.default.fileExists(atPath: cliPath) {
        let cliArgs = ["python3", cliPath] + Array(args.dropFirst(1))
        let cStrings = cliArgs.map { strdup($0) } + [nil]
        execvp("python3", cStrings)
        perror("execvp failed")
        exit(1)
    } else {
        print("Error: aimeter_cli.py not found at \(cliPath)")
        exit(1)
    }
}
```

This must go BEFORE any `NSApplication` or `AppDelegate` initialization. The `execvp` replaces the Swift process entirely with Python — no GUI starts.

- [ ] **Step 2: Verify the binary still compiles**

Run: `swiftc -O -o /tmp/aimeter_test MenuBarApp.swift -framework AppKit -framework Foundation`
Expected: Compiles with no errors

- [ ] **Step 3: Test the delegation**

Run: `/tmp/aimeter_test setup --help 2>&1 || true`
Expected: Either shows the Python CLI output or "aimeter_cli.py not found" (since it's not co-located with `/tmp/aimeter_test`)

- [ ] **Step 4: Commit**

```bash
git add MenuBarApp.swift
git commit -m "feat: delegate 'setup' subcommand to Python CLI via execvp"
```

---

### Task 5: GitHub Actions Release Workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build universal binary
        run: |
          swiftc -O -o aimeter-arm64 -target arm64-apple-macosx12.0 MenuBarApp.swift \
              -framework AppKit -framework Foundation
          swiftc -O -o aimeter-x86_64 -target x86_64-apple-macosx12.0 MenuBarApp.swift \
              -framework AppKit -framework Foundation
          lipo -create -output aimeter aimeter-arm64 aimeter-x86_64
          file aimeter

      - name: Create release tarball
        run: |
          VERSION="${GITHUB_REF#refs/tags/}"
          mkdir -p "aimeter-${VERSION}"
          cp aimeter aimeter_daemon.py aimeter_cli.py \
             index.html index.css dashboard.js \
             com.aimeter.app.plist install.sh \
             "aimeter-${VERSION}/"
          tar czf "aimeter-${VERSION}.tar.gz" "aimeter-${VERSION}"
          shasum -a 256 "aimeter-${VERSION}.tar.gz" > "aimeter-${VERSION}.tar.gz.sha256"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            aimeter-*.tar.gz
            aimeter-*.tar.gz.sha256
          generate_release_notes: true
```

- [ ] **Step 2: Add build artifacts to .gitignore**

Append to `.gitignore`:

```
aimeter-arm64
aimeter-x86_64
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml .gitignore
git commit -m "feat: add GitHub Actions release workflow for universal binary"
```

---

### Task 6: Homebrew Formula (separate repo)

**Files:**
- Create: `Formula/aimeter.rb` in new repo `smriti-memcore/homebrew-tap`

- [ ] **Step 1: Create the Homebrew tap repo**

Run: `gh repo create smriti-memcore/homebrew-tap --public --description "Homebrew tap for AIMeter"`

- [ ] **Step 2: Create the formula**

Create `Formula/aimeter.rb`:

```ruby
class Aimeter < Formula
  desc "Real-time AI API usage and cost monitor for macOS"
  homepage "https://github.com/smriti-memcore/aimeter"
  # URL and sha256 are updated by the release workflow
  url "https://github.com/smriti-memcore/aimeter/releases/download/v0.1.0/aimeter-v0.1.0.tar.gz"
  sha256 "UPDATE_AFTER_FIRST_RELEASE"
  license "MIT"

  depends_on :macos
  depends_on "python@3"

  def install
    # Install everything to libexec first (binary + scripts + assets)
    libexec.install "aimeter", "aimeter_daemon.py", "aimeter_cli.py"
    libexec.install "index.html", "index.css", "dashboard.js"
    libexec.install "com.aimeter.app.plist"

    # Create a bin wrapper that delegates to the libexec binary
    (bin/"aimeter").write_env_script libexec/"aimeter"
  end

  service do
    run [opt_libexec/"aimeter"]
    keep_alive crashed: true
    log_path var/"log/aimeter.log"
    error_log_path var/"log/aimeter.log"
  end

  def caveats
    <<~EOS
      AIMeter is installed! To start on login:
        brew services start aimeter

      Then configure your AI tools:
        aimeter setup

      Dashboard: http://127.0.0.1:5333

      To uninstall cleanly:
        aimeter setup --undo
        brew services stop aimeter
        brew uninstall aimeter
    EOS
  end
end
```

Note: The `url` and `sha256` must be updated after the first release is cut. A future improvement could automate this with a GitHub Action that updates the formula on release.

- [ ] **Step 3: Push to the tap repo**

```bash
cd /tmp && git clone https://github.com/smriti-memcore/homebrew-tap.git
mkdir -p homebrew-tap/Formula
# copy the formula file
cd homebrew-tap
git add Formula/aimeter.rb
git commit -m "feat: add aimeter formula"
git push
```

- [ ] **Step 4: Verify tap works**

Run: `brew tap smriti-memcore/tap`
Expected: Tap added successfully (formula won't install yet — needs a real release tarball)

- [ ] **Step 5: Commit a reference note in the aimeter repo**

No file change needed — the formula lives in the tap repo. This step is just verification.

---

### Task 7: End-to-End Integration Test

- [ ] **Step 1: Run all unit tests**

Run: `python3 -m pytest tests/ -v`
Expected: All PASS

- [ ] **Step 2: Compile the binary locally**

Run: `swiftc -O -o aimeter MenuBarApp.swift -framework AppKit -framework Foundation`
Expected: Compiles successfully

- [ ] **Step 3: Test `aimeter setup` delegation**

Run: `./aimeter setup --help 2>&1 || true`
Expected: Shows usage or runs the setup flow

- [ ] **Step 4: Test install.sh in a temp environment**

Run: `bash -n install.sh`
Expected: No syntax errors

- [ ] **Step 5: Final commit — update README**

Update `README.md` to add the Homebrew install instructions alongside the existing manual instructions. Add a "Quick Start" section at the top:

```markdown
## Quick Start (Homebrew)

brew tap smriti-memcore/tap
brew install aimeter
brew services start aimeter
aimeter setup
```

```bash
git add README.md
git commit -m "docs: add Homebrew install instructions to README"
```
