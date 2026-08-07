#!/bin/bash
set -e

echo "=== AI Cost Control Installer ==="
echo "Compiling the native Menu Bar application on your machine..."

# Verify swiftc is available
if ! command -v swiftc &> /dev/null; then
    echo "❌ Error: Swift compiler (swiftc) not found."
    echo "Please ensure you have macOS Command Line Tools installed."
    echo "You can install them by running: xcode-select --install"
    exit 1
fi

# Compile the Swift application
swiftc MenuBarApp.swift -o AIUsageTracker
echo "✅ Compilation successful! Generated 'AIUsageTracker' executable."

echo ""
echo "=== Setup Instructions ==="
echo "1. Run the app in the background:"
echo "   ./AIUsageTracker &"
echo ""
echo "2. Add these environment variables to your shell profile (~/.zshrc or ~/.bashrc)"
echo "   to track your API calls:"
echo "   "
echo "   export OPENAI_BASE_URL=\"http://127.0.0.1:5333/openai/v1\""
echo "   export ANTHROPIC_BASE_URL=\"http://127.0.0.1:5333/anthropic\""
echo "   "
echo "3. For Claude Code CLI, no setup is needed. The app reads history logs automatically!"
echo ""
echo "4. Open the Web Dashboard:"
echo "   http://127.0.0.1:5333/"
echo "=========================="
