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
