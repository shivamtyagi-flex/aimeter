"""Tests for aimeter_cli.py — auto-setup CLI."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Ensure the parent directory is importable
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import aimeter_cli


class TestDetectTools(unittest.TestCase):
    """Test detect_tools() discovery logic."""

    def test_detects_claude_code(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            home = Path(tmpdir)
            (home / ".claude").mkdir()
            with patch.object(Path, "home", return_value=home):
                tools = aimeter_cli.detect_tools()
        claude = [t for t in tools if t["name"] == "Claude Code"]
        self.assertEqual(len(claude), 1)
        self.assertEqual(claude[0]["mode"], "log_watcher")

    def test_detects_shell_profile(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            home = Path(tmpdir)
            with patch.object(Path, "home", return_value=home):
                tools = aimeter_cli.detect_tools()
        shell = [t for t in tools if t["name"] == "Shell profile"]
        self.assertEqual(len(shell), 1)
        self.assertEqual(shell[0]["mode"], "proxy")


class TestConfigureShellProfile(unittest.TestCase):
    """Test configure_shell_profile() appends exports idempotently."""

    def test_appends_export_lines(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            rc = Path(tmpdir) / ".zshrc"
            rc.write_text("# existing content\n")
            changes = aimeter_cli.configure_shell_profile(str(rc))
            self.assertTrue(len(changes) > 0)
            content = rc.read_text()
            self.assertIn(aimeter_cli.OPENAI_EXPORT, content)
            self.assertIn(aimeter_cli.ANTHROPIC_EXPORT, content)
            self.assertIn(aimeter_cli.AIMETER_MARKER, content)

    def test_idempotent_skips_if_present(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            rc = Path(tmpdir) / ".zshrc"
            rc.write_text(
                f"{aimeter_cli.AIMETER_MARKER}\n"
                f"{aimeter_cli.OPENAI_EXPORT}\n"
                f"{aimeter_cli.ANTHROPIC_EXPORT}\n"
            )
            changes = aimeter_cli.configure_shell_profile(str(rc))
            self.assertEqual(changes, [])


class TestConfigureCursor(unittest.TestCase):
    """Test configure_cursor() sets http.proxy in settings.json."""

    def test_sets_http_proxy_in_new_settings(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            settings = Path(tmpdir) / "settings.json"
            changes = aimeter_cli.configure_cursor(str(settings))
            self.assertTrue(len(changes) > 0)
            data = json.loads(settings.read_text())
            self.assertEqual(data["http.proxy"], aimeter_cli.PROXY_HOST)

    def test_idempotent(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            settings = Path(tmpdir) / "settings.json"
            settings.write_text(json.dumps({"http.proxy": aimeter_cli.PROXY_HOST}))
            changes = aimeter_cli.configure_cursor(str(settings))
            self.assertEqual(changes, [])


class TestConfigureClaudeCode(unittest.TestCase):
    """Test configure_claude_code() returns no changes."""

    def test_returns_no_changes(self):
        changes = aimeter_cli.configure_claude_code()
        self.assertEqual(changes, [])


class TestConfigureVSCode(unittest.TestCase):
    """Test configure_vscode() sets http.proxy via configure_json_settings."""

    def test_sets_http_proxy(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            settings = Path(tmpdir) / "settings.json"
            changes = aimeter_cli.configure_vscode(str(settings))
            self.assertTrue(len(changes) > 0)
            data = json.loads(settings.read_text())
            self.assertEqual(data["http.proxy"], aimeter_cli.PROXY_HOST)


class TestCheckConflicts(unittest.TestCase):
    """Test check_conflicts() detects non-aimeter URLs."""

    def test_detects_non_aimeter_url(self):
        env = {"OPENAI_BASE_URL": "http://other:9999"}
        with patch.dict(os.environ, env, clear=True):
            conflicts = aimeter_cli.check_conflicts()
        self.assertEqual(len(conflicts), 1)
        self.assertEqual(conflicts[0][0], "OPENAI_BASE_URL")

    def test_no_conflict_when_aimeter_url(self):
        env = {"OPENAI_BASE_URL": "http://127.0.0.1:5333/openai/v1"}
        with patch.dict(os.environ, env, clear=True):
            conflicts = aimeter_cli.check_conflicts()
        self.assertEqual(len(conflicts), 0)

    def test_no_conflict_when_unset(self):
        env = os.environ.copy()
        env.pop("OPENAI_BASE_URL", None)
        env.pop("ANTHROPIC_BASE_URL", None)
        with patch.dict(os.environ, env, clear=True):
            conflicts = aimeter_cli.check_conflicts()
        self.assertEqual(len(conflicts), 0)


class TestUndo(unittest.TestCase):
    """Test that undo reverses shell profile changes."""

    def test_undo_removes_shell_exports(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            rc = Path(tmpdir) / ".zshrc"
            rc.write_text("# my shell config\n")
            state_path = Path(tmpdir) / "state.json"

            # Configure
            changes = aimeter_cli.configure_shell_profile(str(rc))
            self.assertTrue(len(changes) > 0)
            self.assertIn(aimeter_cli.OPENAI_EXPORT, rc.read_text())

            # Save state
            state = {
                "configured": [{
                    "name": "Shell profile",
                    "config_path": str(rc),
                    "changes": changes,
                }]
            }
            aimeter_cli.write_setup_state(state, path=str(state_path))

            # Undo
            with patch.object(aimeter_cli, "STATE_FILE", state_path):
                with patch.object(aimeter_cli, "read_setup_state", lambda path=None: aimeter_cli.read_setup_state.__wrapped__(path) if hasattr(aimeter_cli.read_setup_state, '__wrapped__') else json.loads(state_path.read_text())):
                    aimeter_cli.run_undo()

            content = rc.read_text()
            self.assertNotIn(aimeter_cli.OPENAI_EXPORT, content)
            self.assertNotIn(aimeter_cli.ANTHROPIC_EXPORT, content)
            self.assertIn("# my shell config", content)


class TestSetupState(unittest.TestCase):
    """Test read/write roundtrip for setup state."""

    def test_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            state_path = Path(tmpdir) / "sub" / "state.json"
            data = {"configured": [{"name": "test", "changes": ["a"]}]}
            aimeter_cli.write_setup_state(data, path=str(state_path))
            loaded = aimeter_cli.read_setup_state(path=str(state_path))
            self.assertEqual(loaded, data)

    def test_read_missing_file(self):
        result = aimeter_cli.read_setup_state(path="/tmp/nonexistent_aimeter_test.json")
        self.assertEqual(result, {})


if __name__ == "__main__":
    unittest.main()
