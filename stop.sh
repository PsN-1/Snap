#!/bin/bash

# Stop script for Snap - Dock App Launcher
# Kills Snap only if it's currently running.

set -e

echo "🔍 Checking for running Snap instances..."

if pgrep -f "./snap" > /dev/null 2>&1 || pgrep -x "snap" > /dev/null 2>&1; then
    echo "⚠️  Found running instance(s), killing..."
    pkill -f "./snap" 2>/dev/null || true
    pkill -x "snap" 2>/dev/null || true
    sleep 1  # Give it a moment to fully terminate
    echo "✅ Stopped Snap"
else
    echo "✅ Snap is not running"
fi

