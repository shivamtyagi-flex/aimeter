#!/bin/bash
set -e

echo "=== Building AIMeter macOS App Bundle ==="

APP_DIR="AIMeter.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MAC_DIR="${CONTENTS_DIR}/MacOS"
RES_DIR="${CONTENTS_DIR}/Resources"

# Clean previous build
rm -rf "$APP_DIR"

# Create directory structure
mkdir -p "$MAC_DIR"
mkdir -p "$RES_DIR"

# Compile Swift code to binary
echo "Compiling Swift GUI application..."
swiftc MenuBarApp.swift -o "${MAC_DIR}/aimeter"

# Copy python and dashboard resources
echo "Copying scripts and resources..."
cp aimeter_daemon.py "$RES_DIR/"
cp aimeter_cli.py "$RES_DIR/"
cp index.html "$RES_DIR/"
cp index.css "$RES_DIR/"
cp dashboard.js "$RES_DIR/"
cp com.aimeter.app.plist "$RES_DIR/"

# Generate Info.plist
echo "Generating Info.plist..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>aimeter</string>
    <key>CFBundleIdentifier</key>
    <string>com.smriti.aimeter</string>
    <key>CFBundleName</key>
    <string>AIMeter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.2</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "✔ Successfully created ${APP_DIR}!"
echo "You can launch the app by double-clicking it in Finder or running:"
echo "  open ${APP_DIR}"
