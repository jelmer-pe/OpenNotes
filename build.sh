#!/bin/bash
# Build Open Notes as a proper .app bundle
set -e

cd "$(dirname "$0")"

# --- Check prerequisites ---
missing=()

if ! command -v swift &> /dev/null; then
    missing+=("Swift (install Xcode or Xcode Command Line Tools)")
fi

if ! command -v node &> /dev/null; then
    missing+=("Node.js (https://nodejs.org)")
fi

if [ ${#missing[@]} -ne 0 ]; then
    echo "Missing prerequisites:"
    for dep in "${missing[@]}"; do
        echo "  - $dep"
    done
    exit 1
fi

# --- Build web editor ---
echo "Building web editor..."
cd WebEditor
npm install --silent
npm run build --silent
cd ..

# --- Copy web editor assets into SPM resources ---
cp WebEditor/dist/editor.bundle.js LocalNotes/Resources/editor.bundle.js
cp WebEditor/src/editor.html LocalNotes/Resources/editor.html
cp WebEditor/src/editor.css LocalNotes/Resources/editor.css

# --- Build Swift app ---
echo "Building app..."
swift build -c release 2>&1 | tail -5

# --- Assemble .app bundle ---
APP_DIR="Open Notes.app/Contents"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp .build/release/LocalNotes "$APP_DIR/MacOS/LocalNotes"
cp LocalNotes/Info.plist "$APP_DIR/Info.plist"
cp .build/release/LocalNotes_LocalNotes.bundle/editor.html "$APP_DIR/Resources/"
cp .build/release/LocalNotes_LocalNotes.bundle/editor.bundle.js "$APP_DIR/Resources/"
cp .build/release/LocalNotes_LocalNotes.bundle/editor.css "$APP_DIR/Resources/"

echo ""
echo "Done! Built Open Notes.app"
echo "  Run with: open \"Open Notes.app\""
echo "  Or install to /Applications: cp -r \"Open Notes.app\" /Applications/"
