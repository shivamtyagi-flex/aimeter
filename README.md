<p align="center">
  <img src="assets/app_icon.png" alt="AIMeter Icon" width="128" height="128">
</p>

<h1 align="center">🤖 AIMeter</h1>

<p align="center">
A real-time, pay-as-you-go AI API usage and cost monitor for macOS.<br>
Featuring a native status bar widget and a gorgeous glassmorphic web control center.
</p>

<p align="center">

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)
![Python](https://img.shields.io/badge/Python-3.9+-yellow.svg)

</p>

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

## Installation

### 🚀 Option 1: DMG Installer (Recommended)

1. Head to the [Releases Page](https://github.com/smriti-memcore/aimeter/releases) and download the latest `AIMeter.dmg` file.
2. Double-click to open the DMG, then drag **AIMeter.app** into your `/Applications` directory.
3. Open **AIMeter** from your Applications folder. The CPU status icon will appear in your top macOS menu bar.
4. Click the CPU menu bar icon and select **"Configure Shell & IDEs..."** to automatically open a terminal session and configure tracking across all local AI tools (Zsh, Cursor settings, etc.).

*Note: On your very first run, macOS Gatekeeper may block launch. To bypass, simply right-click **AIMeter.app** in Finder and choose **Open**.*

---

### 🍺 Option 2: Homebrew

If you prefer managing your tools via the command line:

```bash
brew tap smriti-memcore/aimeter
brew install aimeter
brew services start aimeter                        # Start the background proxy daemon
aimeter setup                                      # Setup shell/Cursor config & load menu bar agent
```

#### Stopping and Uninstalling (Homebrew):

```bash
# To stop services and undo configurations:
aimeter setup --undo
brew services stop aimeter

# To uninstall cleanly:
brew uninstall aimeter
brew untap smriti-memcore/aimeter
```

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
