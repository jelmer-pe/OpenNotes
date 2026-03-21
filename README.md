# Open Notes

A lightweight macOS menu bar notes app with a floating panel that stays on top of your windows. Notes are stored as plain files in `~/Documents/Notes/` — no database, no sync service, just your files.

## Prerequisites

- macOS 14 (Sonoma) or later
- Swift 5.9+
- Node.js (for building the web editor)

## Building

```bash
./build.sh
```

This handles everything — installs web editor dependencies, builds the editor, compiles the Swift app, and produces `Open Notes.app` in the project root. The script will let you know if any prerequisites are missing.

To run:

```bash
open "Open Notes.app"
```

Or install to Applications:

```bash
cp -r "Open Notes.app" /Applications/
```

## Usage

Open Notes lives in your **menu bar**. Toggle the floating panel with the global hotkey **Option+N**, or click the menu bar icon.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| **Option+N** | Show/hide panel (works globally) |
| **Cmd+N** | New note |
| **Cmd+P** | Open note browser |
| **Cmd+K** | Shortcuts palette |
| **Cmd+[** / **Cmd+]** | Navigate back / forward |
| **Cmd+Backspace** | Delete current note (with confirmation) |
| **Cmd+B** | Bold |
| **Cmd+I** | Italic |
| **Cmd+Shift+S** | Strikethrough |
| **Cmd+Shift+B** | Blockquote |
| **Cmd+Shift+7** | Bullet list |
| **Cmd+Shift+8** | Ordered list |
| **Cmd+Shift+Enter** | To-do / checkbox list |
| **Cmd+Option+C** | Code block |
| **Ctrl+Cmd+Up/Down** | Reorder list items |

### Storage

Notes are saved as files in `~/Documents/Notes/`. Each note is a `.md` file with a date-prefixed filename (e.g. `2026-03-20-my-note.md`). The filename automatically updates when you change the note title.

## Project structure

```
OpenNotes/
├── LocalNotes/              # Swift app
│   ├── LocalNotesApp.swift  # App entry point, menu bar, key handling
│   ├── AppState.swift       # Shared app state
│   ├── Models/
│   │   └── Note.swift       # Note data model
│   ├── Services/
│   │   └── NoteStore.swift  # File-based note storage
│   ├── Views/
│   │   ├── EditorView.swift     # Main editor layout
│   │   ├── EditorWebView.swift  # WKWebView wrapper
│   │   ├── FloatingPanel.swift  # Floating NSPanel
│   │   └── NoteBrowser.swift    # Note browser overlay (Cmd+P)
│   └── Resources/           # Bundled web editor assets
├── WebEditor/               # TipTap rich-text editor (JavaScript)
│   └── src/
│       ├── editor.js        # Editor setup and bridge to Swift
│       ├── editor.html      # Editor HTML shell
│       └── editor.css       # Editor styles
├── Package.swift            # Swift Package Manager config
└── build.sh                 # Build script
```
