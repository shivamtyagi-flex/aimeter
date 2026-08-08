#!/usr/bin/env python3
"""AIMeter auto-setup CLI — detect AI tools and configure proxy routing."""

import json
import os
import sys
from pathlib import Path

PROXY_HOST = "http://127.0.0.1:5333"
OPENAI_EXPORT = 'export OPENAI_BASE_URL="http://127.0.0.1:5333/openai/v1"'
ANTHROPIC_EXPORT = 'export ANTHROPIC_BASE_URL="http://127.0.0.1:5333/anthropic"'
AIMETER_MARKER = "# Added by aimeter setup"

STATE_DIR = Path.home() / ".aimeter"
STATE_FILE = STATE_DIR / "setup_state.json"
LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"
PLIST_NAME = "com.aimeter.app.plist"
PLIST_DST = LAUNCH_AGENTS_DIR / PLIST_NAME


def detect_tools():
    """Detect AI tools installed on the system.

    Returns a list of dicts: {name, mode, config_path, status}.
    """
    tools = []
    home = Path.home()

    # Claude Code — tracked via log watcher, no config changes
    claude_dir = home / ".claude"
    if claude_dir.exists():
        tools.append({
            "name": "Claude Code",
            "mode": "log_watcher",
            "config_path": str(claude_dir),
            "status": "detected",
        })

    # Cursor
    cursor_settings = home / "Library" / "Application Support" / "Cursor" / "User" / "settings.json"
    if cursor_settings.parent.exists():
        tools.append({
            "name": "Cursor",
            "mode": "proxy",
            "config_path": str(cursor_settings),
            "status": "detected",
        })

    # VS Code
    vscode_settings = home / "Library" / "Application Support" / "Code" / "User" / "settings.json"
    if vscode_settings.parent.exists():
        tools.append({
            "name": "VS Code",
            "mode": "proxy",
            "config_path": str(vscode_settings),
            "status": "detected",
        })

    # Shell profile
    shell = os.environ.get("SHELL", "/bin/zsh")
    if "zsh" in shell:
        rc_path = home / ".zshrc"
    else:
        rc_path = home / ".bashrc"
    tools.append({
        "name": "Shell profile",
        "mode": "proxy",
        "config_path": str(rc_path),
        "status": "detected",
    })

    return tools


def configure_shell_profile(rc_path):
    """Append OPENAI_BASE_URL and ANTHROPIC_BASE_URL exports to a shell profile.

    Idempotent: skips lines that already exist.
    Returns a list of change description strings.
    """
    rc_path = Path(rc_path)
    existing = rc_path.read_text() if rc_path.exists() else ""

    lines_to_add = []
    if OPENAI_EXPORT not in existing:
        lines_to_add.append(OPENAI_EXPORT)
    if ANTHROPIC_EXPORT not in existing:
        lines_to_add.append(ANTHROPIC_EXPORT)

    if not lines_to_add:
        return []

    block = f"\n{AIMETER_MARKER}\n" + "\n".join(lines_to_add) + "\n"
    with open(rc_path, "a") as f:
        f.write(block)

    return [f"Added to {rc_path}: {line}" for line in lines_to_add]


def configure_json_settings(settings_path, key, value):
    """Set a key in a JSON settings file (e.g. Cursor or VS Code settings.json).

    Idempotent: skips if key already has the desired value.
    Returns a list of change description strings.
    """
    settings_path = Path(settings_path)
    if settings_path.exists():
        try:
            data = json.loads(settings_path.read_text())
        except (json.JSONDecodeError, ValueError):
            data = {}
    else:
        data = {}

    if data.get(key) == value:
        return []

    data[key] = value
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    return [f"Set {key}={value} in {settings_path}"]


def configure_cursor(settings_path):
    """Configure Cursor to use the aimeter proxy."""
    return configure_json_settings(settings_path, "http.proxy", PROXY_HOST)


def configure_vscode(settings_path):
    """Configure VS Code to use the aimeter proxy."""
    return configure_json_settings(settings_path, "http.proxy", PROXY_HOST)


def configure_claude_code():
    """Claude Code is tracked via log watcher — no config changes needed."""
    return []


def check_conflicts():
    """Check for existing non-aimeter proxy URLs.

    Returns a list of (var_name, current_value) tuples for conflicts found.
    """
    conflicts = []
    for var in ("OPENAI_BASE_URL", "ANTHROPIC_BASE_URL"):
        val = os.environ.get(var, "")
        if val and PROXY_HOST not in val:
            conflicts.append((var, val))
    return conflicts


def install_launch_agent():
    """Install the LaunchAgent plist for the menu bar app."""
    exe_path = os.path.realpath(sys.argv[0])
    cli_dir = Path(exe_path).parent
    plist_src = cli_dir / PLIST_NAME

    if not plist_src.exists():
        plist_src = cli_dir.parent / PLIST_NAME
    if not plist_src.exists():
        return []

    if PLIST_DST.exists():
        return []

    aimeter_bin = cli_dir / "aimeter"
    if not aimeter_bin.exists():
        aimeter_bin = Path(os.path.realpath(cli_dir / "aimeter"))

    content = plist_src.read_text()
    content = content.replace("__AIMETER_BIN__", str(aimeter_bin))
    content = content.replace("__HOME__", str(Path.home()))

    LAUNCH_AGENTS_DIR.mkdir(parents=True, exist_ok=True)
    PLIST_DST.write_text(content)

    os.system(f"launchctl load {PLIST_DST}")
    return [f"Installed LaunchAgent: {PLIST_DST}"]


def uninstall_launch_agent():
    """Remove the LaunchAgent plist."""
    if PLIST_DST.exists():
        os.system(f"launchctl unload {PLIST_DST}")
        PLIST_DST.unlink()
        return [f"Removed LaunchAgent: {PLIST_DST}"]
    return []


def read_setup_state(path=None):
    """Read the setup state file. Returns a dict."""
    state_path = Path(path) if path else STATE_FILE
    if state_path.exists():
        try:
            return json.loads(state_path.read_text())
        except (json.JSONDecodeError, ValueError):
            return {}
    return {}


def write_setup_state(state, path=None):
    """Write the setup state file."""
    state_path = Path(path) if path else STATE_FILE
    state_path.parent.mkdir(parents=True, exist_ok=True)
    with open(state_path, "w") as f:
        json.dump(state, f, indent=2)
        f.write("\n")


def prompt_yn(message, default=True):
    """Prompt for yes/no input. Returns bool."""
    suffix = " [Y/n] " if default else " [y/N] "
    try:
        answer = input(message + suffix).strip().lower()
    except (EOFError, KeyboardInterrupt):
        print()
        return False
    if not answer:
        return default
    return answer in ("y", "yes")


def run_setup(force=False):
    """Main setup flow: detect tools, prompt user, configure."""
    conflicts = check_conflicts()
    if conflicts and not force:
        print("Conflicts detected:")
        for var, val in conflicts:
            print(f"  {var} = {val}")
        print("Use --force to override, or unset these variables first.")
        return

    tools = detect_tools()
    if not tools:
        print("No AI tools detected.")
        return

    print("Detected AI tools:")
    for t in tools:
        print(f"  - {t['name']} ({t['mode']})")
    print()

    all_changes = []
    state = read_setup_state()
    state.setdefault("configured", [])

    for tool in tools:
        if tool["mode"] == "log_watcher":
            print(f"{tool['name']}: tracked via log watcher (no config changes needed)")
            changes = configure_claude_code()
        elif tool["name"] == "Shell profile":
            if not prompt_yn(f"Configure {tool['name']} ({tool['config_path']})?"):
                continue
            changes = configure_shell_profile(tool["config_path"])
        elif tool["name"] == "Cursor":
            if not prompt_yn(f"Configure {tool['name']} ({tool['config_path']})?"):
                continue
            changes = configure_cursor(tool["config_path"])
        elif tool["name"] == "VS Code":
            if not prompt_yn(f"Configure {tool['name']} ({tool['config_path']})?"):
                continue
            changes = configure_vscode(tool["config_path"])
        else:
            continue

        if changes:
            all_changes.extend(changes)
            state["configured"].append({
                "name": tool["name"],
                "config_path": tool["config_path"],
                "changes": changes,
            })

    la_changes = install_launch_agent()
    all_changes.extend(la_changes)

    if all_changes:
        write_setup_state(state)
        print("\nChanges applied:")
        for c in all_changes:
            print(f"  {c}")
        print(f"\nState saved. Run with --undo to reverse changes.")
    else:
        print("\nNo changes needed — already configured.")


def run_undo():
    """Reverse all changes recorded in setup state."""
    state = read_setup_state()
    configured = state.get("configured", [])
    if not configured:
        print("Nothing to undo.")
        return

    for entry in configured:
        name = entry["name"]
        config_path = Path(entry["config_path"])

        if name == "Shell profile":
            if config_path.exists():
                content = config_path.read_text()
                # Remove the aimeter block: marker line + export lines
                lines = content.split("\n")
                new_lines = []
                skip = False
                for line in lines:
                    if line.strip() == AIMETER_MARKER:
                        skip = True
                        continue
                    if skip and (
                        line.strip().startswith("export OPENAI_BASE_URL=")
                        or line.strip().startswith("export ANTHROPIC_BASE_URL=")
                    ):
                        continue
                    skip = False
                    new_lines.append(line)
                config_path.write_text("\n".join(new_lines))
                print(f"Reverted {config_path}")

        elif name in ("Cursor", "VS Code"):
            if config_path.exists():
                try:
                    data = json.loads(config_path.read_text())
                    if "http.proxy" in data:
                        del data["http.proxy"]
                        with open(config_path, "w") as f:
                            json.dump(data, f, indent=2)
                            f.write("\n")
                    print(f"Reverted {config_path}")
                except (json.JSONDecodeError, ValueError):
                    print(f"Warning: could not parse {config_path}")

    la_changes = uninstall_launch_agent()
    for c in la_changes:
        print(f"  {c}")

    # Clear state
    state["configured"] = []
    write_setup_state(state)
    print("Undo complete.")


def main():
    """Parse arguments and dispatch."""
    args = sys.argv[1:]
    force = "--force" in args
    undo = "--undo" in args

    if undo:
        run_undo()
    else:
        run_setup(force=force)


if __name__ == "__main__":
    main()
