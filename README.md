# 🤖 AIMeter

A real-time, pay-as-you-go AI API usage and cost monitor for macOS. Featuring a native status bar widget and a gorgeous glassmorphic web control center.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)
![Python](https://img.shields.io/badge/Python-3.9+-yellow.svg)

---

## Key Features

*   **Native macOS Menu Bar App**: A lightweight Swift-compiled helper displaying your daily spend directly on your status bar. Integrates automatically with macOS dark/light themes.
*   **API Interception Proxy**: A zero-dependency local proxy running on port `5333` that intercepts OpenAI, Gemini, Anthropic, and OpenRouter API calls to log tokens and calculate exact costs instantly.
*   **Claude Code Watcher**: Background thread monitoring CLI conversation logs (`~/.claude/projects/`) to parse, match, and sync your Claude CLI costs automatically.
*   **Premium Web Control Center**: A stunning, glassmorphic dark-themed analytics dashboard:
    *   *Visual Budget Progress*: Outer dial updates shape and color based on daily spending ratio.
    *   *Weekly Spend Trend*: Dynamic SVG sparklines detailing your spend over the past 7 days.
    *   *Live Timeline Stream*: A vertical feed detailing relative timestamps, model tags, and token ratios.
    *   *Drawer Configs*: Slide-out panel for setting daily budget goals and custom model pricing overrides.

---

## Quick Start (Homebrew)

```bash
brew tap smriti-memcore/aimeter
brew install aimeter
brew services start aimeter          # start the daemon (proxy + dashboard)
aimeter setup                        # configure AI tools + install menu bar app
launchctl load ~/Library/LaunchAgents/com.aimeter.app.plist  # start menu bar (auto-starts on login after this)
```

Dashboard: [http://127.0.0.1:5333](http://127.0.0.1:5333)

To stop:

```bash
launchctl unload ~/Library/LaunchAgents/com.aimeter.app.plist
brew services stop aimeter
aimeter setup --undo
```

To uninstall:

```bash
aimeter setup --undo
launchctl unload ~/Library/LaunchAgents/com.aimeter.app.plist
rm ~/Library/LaunchAgents/com.aimeter.app.plist
brew services stop aimeter
brew uninstall aimeter
brew untap smriti-memcore/aimeter
```

---

## Manual Installation

### 1. Prerequisites
Ensure you have the macOS Command Line Tools (for `swiftc` compiler) installed:
```bash
xcode-select --install
```

### 2. Build AIMeter
Clone the repository and run the automated installer:
```bash
chmod +x install.sh
./install.sh
```
*This compiles the Swift status bar app specifically for your processor (Intel or Apple Silicon).*

### 3. Launch the App
Run the compiled binary in the background:
```bash
./aimeter &
```
*The native status bar app will appear in your Mac's top menu bar (represented by a CPU chip icon).*

---

## Routing API Spend

To track costs in your IDEs (Cursor, VS Code), scripts, or console commands, redirect their endpoint addresses to the local proxy:

### Shell Configuration
Add these to your shell profile (`~/.zshrc` or `~/.bashrc`) to apply tracking globally to CLI tools:
```bash
export OPENAI_BASE_URL="http://127.0.0.1:5333/openai/v1"
export ANTHROPIC_BASE_URL="http://127.0.0.1:5333/anthropic"
```

### Custom Scripts (Python Example)
```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:5333/openai/v1",
    api_key="your-real-openai-key"
)
```

---

## Control Center Dashboard

Open your web browser and navigate to:
```text
http://127.0.0.1:5333/
```
From here you can monitor real-time token throughput, see cost graphs, reset today's statistics, or click **Control Center** to toggle the configuration drawer.

---

## File Footprint

All persistence files are saved locally on your drive:
*   **Database**: `~/.aimeter/usage.db` (SQLite storage for logs and overrides).
*   **Cache Registry**: `~/.aimeter/model_prices.json` (Local copy of LiteLLM pricing).
*   **Logs**: `~/.aimeter/daemon.log` (Diagnostics for daemon processes).

---

## License

This project is licensed under the MIT License.
