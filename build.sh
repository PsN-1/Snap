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
    disown
    echo "✅ Snap is now running in the background (PID: $!)"
    echo "   You can continue using this terminal."
else
    echo "❌ Build failed!"
    exit 1
fi

