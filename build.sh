#!/bin/bash
# Build Open Notes as a proper .app bundle
set -e

cd "$(dirname "$0")"

# Copy latest web editor files into SPM resources
cp WebEditor/dist/editor.bundle.js LocalNotes/Resources/editor.bundle.js
cp WebEditor/src/editor.html LocalNotes/Resources/editor.html
cp WebEditor/src/editor.css LocalNotes/Resources/editor.css

echo "Building..."
swift build -c release 2>&1 | tail -5

APP_DIR="Open Notes.app/Contents"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

# Copy executable
cp .build/release/LocalNotes "$APP_DIR/MacOS/LocalNotes"

# Copy Info.plist
cp LocalNotes/Info.plist "$APP_DIR/Info.plist"

# Copy web editor resources
cp .build/release/LocalNotes_LocalNotes.bundle/editor.html "$APP_DIR/Resources/"
cp .build/release/LocalNotes_LocalNotes.bundle/editor.bundle.js "$APP_DIR/Resources/"
cp .build/release/LocalNotes_LocalNotes.bundle/editor.css "$APP_DIR/Resources/"

echo ""
echo "✓ Built Open Notes.app"
echo "  Run with: open \"Open Notes.app\""
echo "  Or install to /Applications: cp -r \"Open Notes.app\" /Applications/"
