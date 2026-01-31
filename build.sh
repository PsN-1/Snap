#!/bin/bash

# Build script for Snap - Dock App Launcher
# Compiles Snap.swift into a standalone executable

set -e  # Exit on error

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

echo "🔨 Building Snap..."
swiftc -o snap Snap.swift -framework Cocoa -framework Carbon

if [ $? -eq 0 ]; then
    echo "✅ Build successful! Executable created: ./snap"
    echo "🚀 Launching Snap in background..."
    nohup ./snap > /dev/null 2>&1 &
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

