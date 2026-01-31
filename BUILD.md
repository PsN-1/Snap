# Building Standalone Snap.app

## Quick Build

### Option 1: Using Xcode (Easiest)

1. Open `Snap.xcodeproj` in Xcode
2. Select **Product > Archive** (or press `Cmd+B` to build)
3. The app will be built at:
   ```
   ~/Library/Developer/Xcode/DerivedData/Snap-*/Build/Products/Release/Snap.app
   ```
4. Copy `Snap.app` to your Applications folder or anywhere you want

### Option 2: Using Command Line

Run the build script:
```bash
./build-app.sh
```

This will create `Snap.app` in the current directory.

### Option 3: Manual Build

```bash
xcodebuild -project Snap.xcodeproj \
           -scheme Snap \
           -configuration Release \
           clean build
```

Then find the app in:
```
~/Library/Developer/Xcode/DerivedData/Snap-*/Build/Products/Release/Snap.app
```

## Using the App

1. **Double-click** `Snap.app` to run it
2. The app runs in the background (no dock icon)
3. Grant accessibility permissions when prompted
4. Press `Ctrl+1` through `Ctrl+9` to launch apps

## Distribution

You can:
- **Copy to Applications**: Drag `Snap.app` to `/Applications`
- **Share with others**: Send them the `Snap.app` folder
- **Run from anywhere**: The app is self-contained

## Note

The first time someone runs the app, macOS may show a security warning because it's not code-signed. They can:
1. Right-click the app
2. Select "Open"
3. Click "Open" in the security dialog

Or add it to System Settings > Privacy & Security > Developer Tools

