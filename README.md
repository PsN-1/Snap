# Snap - Dock App Launcher

A macOS application that allows you to launch apps from your dock using keyboard shortcuts based on their position.

## Features

- 🚀 Launch dock apps instantly with `Ctrl+1` through `Ctrl+9`
- 🔄 Automatically refreshes dock app positions every 5 seconds
- 📍 Maps keyboard shortcuts to dock positions dynamically
- ⚡ Fast and lightweight
- 🍎 Native Swift implementation for better macOS integration

## Requirements

- macOS 12.0 or later
- Swift 5.9 or later
- Accessibility permissions (required for dock monitoring)

## Installation

### Build and Run Script (Recommended)

Use the provided build script to compile and automatically launch the app:
```bash
./build.sh
```

This script will:
- Check for and kill any running instances
- Compile the app
- Launch it in the background automatically

### Quick Build

Compile directly with Swift:
```bash
swiftc -o snap Snap.swift -framework Cocoa -framework Carbon
```

This will create a `snap` executable in the current directory.

### Using Swift Package Manager (Optional)

If you prefer using SPM:
```bash
swift build -c release
```

The binary will be created at `.build/release/snap`

## Setup

### Grant Accessibility Permissions

Before running the app, you need to grant it accessibility permissions:

1. Run the app once (it will prompt you)
2. Go to **System Settings** > **Privacy & Security** > **Accessibility**
3. Click the lock icon to make changes (enter your password)
4. Find "snap" in the list and enable it
5. If "snap" doesn't appear, click the `+` button and add the built executable

## Usage

1. Run the application:
   
   **Using the build script (recommended):**
   ```bash
   ./build.sh
   ```
   This will build and launch the app automatically in the background.
   
   **Or run manually:**
   ```bash
   .build/release/snap
   ```
   
   Or if you built manually:
   ```bash
   ./snap
   ```

2. The app will display the current dock mapping:
   ```
   📌 Current dock mapping:
     Ctrl+1 → Safari
     Ctrl+2 → Mail
     Ctrl+3 → Messages
     ...
   ```

3. Press `Ctrl+1` through `Ctrl+9` to launch apps from your dock based on their position

4. The dock mapping refreshes automatically every 5 seconds to stay in sync with your dock

5. Press `Ctrl+C` to quit the application

## How It Works

- The app monitors your dock using AppleScript
- It maps the first 9 apps in your dock to keyboard shortcuts `Ctrl+1` through `Ctrl+9`
- Uses macOS Carbon APIs to register global hotkeys
- Launches apps using AppleScript when shortcuts are pressed
- Built with Swift for native macOS integration

## Troubleshooting

### Hotkeys not working

1. Make sure accessibility permissions are granted (see Setup section)
2. Check that the app is running (you should see the dock mapping when it starts)
3. Try restarting the app
4. If running in Terminal, Control keys may be intercepted - try running the app outside Terminal

### Apps not launching

- Make sure the app name in the dock matches exactly
- Some apps might have different names than expected
- Check the console output for error messages

### Dock positions not updating

- The app refreshes every 5 seconds automatically
- If positions seem wrong, try restarting the app
- Make sure you haven't moved apps in the dock since the last refresh

## Building for Distribution

To create a standalone binary:

```bash
swiftc -o snap Snap.swift -framework Cocoa -framework Carbon
```

You can copy the binary to `/usr/local/bin` or anywhere in your PATH:

```bash
cp snap /usr/local/bin/
```

Or install it globally:
```bash
sudo cp snap /usr/local/bin/
```

## License

This project is open source and available for personal use.
# Snap
