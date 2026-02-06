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

# Function to ask about Finder handling
choose_finder() {
    # Check if we're in an interactive terminal
    if [ ! -t 0 ]; then
        # Not interactive, default to ignore
        echo "ignore"
        return
    fi
    
    echo "" >&2
    echo "Finder handling:" >&2
    echo "  By default, Finder is ignored in the dock mapping." >&2
    echo "  You can instead assign it to a specific key (1-0)." >&2
    echo "" >&2
    
    while true; do
        echo -n "Ignore Finder in dock mapping? (Y/n): " >&2
        read answer
        answer=${answer:-Y}
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
        
        if [ "$answer" = "n" ] || [ "$answer" = "no" ]; then
            # Ask which key
            while true; do
                echo -n "Which key (1-0) should launch Finder? " >&2
                read key
                key=$(echo "$key" | tr '[:upper:]' '[:lower:]')
                
                if [ "$key" = "0" ]; then
                    echo "10"
                    return
                elif [ "$key" -ge 1 ] && [ "$key" -le 9 ] 2>/dev/null; then
                    echo "$key"
                    return
                else
                    echo "Invalid choice. Please enter 1-9 or 0." >&2
                fi
            done
        elif [ "$answer" = "y" ] || [ "$answer" = "yes" ] || [ -z "$answer" ]; then
            echo "ignore"
            return
        else
            echo "Invalid choice. Please enter Y or n." >&2
        fi
    done
}

# Prompt user about Finder handling
FINDER_CONFIG=$(choose_finder)
if [ "$FINDER_CONFIG" = "ignore" ]; then
    echo "✅ Finder will be ignored"
else
    echo "✅ Finder will be mapped to key: $FINDER_CONFIG"
fi
echo ""

echo "🔨 Building Snap..."
swiftc -o snap Snap.swift -framework Cocoa -framework Carbon

if [ $? -eq 0 ]; then
    echo "✅ Build successful! Executable created: ./snap"
    echo "🚀 Launching Snap in background..."
    nohup ./snap "$MODIFIER" "$FINDER_CONFIG" > /dev/null 2>&1 &
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

