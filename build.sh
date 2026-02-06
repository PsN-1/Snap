#!/bin/bash

# Build script for Snap - Dock App Launcher
# Compiles Snap.swift into a standalone executable

set -e  # Exit on error

# Function to show interactive menu
choose_modifier() {
    # Check if we're in an interactive terminal
    if [ ! -t 0 ]; then
        # Not interactive, default to option
        echo "option" >&1
        return
    fi
    
    # Print menu to stderr so it displays while output is captured
    echo "" >&2
    echo "Select modifier key:" >&2
    echo "" >&2
    echo "  1) Control" >&2
    echo "  2) Command" >&2
    echo "  3) Option" >&2
    echo "" >&2
    
    while true; do
        echo -n "Enter choice [1-3] (default: 3): " >&2
        read choice
        choice=${choice:-3}
        
        case "$choice" in
            1)
                echo "control"
                return
                ;;
            2)
                echo "command"
                return
                ;;
            3)
                echo "option"
                return
                ;;
            *)
                echo "Invalid choice. Please enter 1, 2, or 3." >&2
                ;;
        esac
    done
}

# Check for running instances and kill them
echo "🔍 Checking for running instances..."
if pgrep -f "./snap" > /dev/null 2>&1 || pgrep -x "snap" > /dev/null 2>&1; then
    echo "⚠️  Found running instance(s), killing..."
    pkill -f "./snap" 2>/dev/null || true
    pkill -x "snap" 2>/dev/null || true
    sleep 1  # Give it a moment to fully terminate
    echo "✅ Killed existing instance(s)"
else
    echo "✅ No running instances found"
fi

# Prompt user to choose modifier key
MODIFIER=$(choose_modifier)
echo "✅ Selected modifier: $MODIFIER"
echo ""

echo "🔨 Building Snap..."
swiftc -o snap Snap.swift -framework Cocoa -framework Carbon

if [ $? -eq 0 ]; then
    echo "✅ Build successful! Executable created: ./snap"
    echo "🚀 Launching Snap in background with modifier: $MODIFIER..."
    nohup ./snap "$MODIFIER" > /dev/null 2>&1 &
    pid=$!
    disown
    sleep 0.2
    if kill -0 "$pid" 2>/dev/null; then
        rm -f ./snap
        echo "🧹 Removed ./snap from disk after launch"
    else
        echo "⚠️  Snap exited immediately; keeping ./snap for debugging"
    fi
    echo "✅ Snap is now running in the background (PID: $pid)"
    echo "   You can continue using this terminal."
else
    echo "❌ Build failed!"
    exit 1
fi

