#!/bin/bash

# Build script to create a standalone Snap.app

echo "🔨 Building Snap.app..."

# Build the app in Release mode
xcodebuild -project Snap.xcodeproj \
           -scheme Snap \
           -configuration Release \
           -derivedDataPath ./build \
           clean build

# Find the built app
APP_PATH=$(find ./build -name "Snap.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Error: Could not find built app"
    exit 1
fi

# Copy to current directory
echo "📦 Copying app to current directory..."
cp -R "$APP_PATH" ./Snap.app

echo "✅ Done! Snap.app is ready in the current directory"
echo "   You can now:"
echo "   - Double-click Snap.app to run it"
echo "   - Drag it to Applications folder"
echo "   - Distribute it to others"

