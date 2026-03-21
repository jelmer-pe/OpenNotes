import SwiftUI
import WebKit
import HotKey

@main
struct LocalNotesApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Open Notes", systemImage: "note.text") {
            Button("Show/Hide Notes") {
                appDelegate.togglePanel()
            }
            .keyboardShortcut("n", modifiers: [.option])

            Divider()

            Button("New Note") {
                appState.createNewNote()
                appDelegate.showPanel()
            }

            Divider()

            Button("Quit") {
                appState.flushSave()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        // Hidden window — we use the floating panel instead
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel?
    var appState: AppState?
    var hotKey: HotKey?
    var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.setupPanel()
            self?.setupHotKey()
            self?.setupKeyMonitor()
            self?.showPanel()
        }
    }

    func setupPanel() {
        guard panel == nil else { return }

        let appState = AppState()
        self.appState = appState

        let editorView = EditorView(appState: appState)
        let hostingView = NSHostingView(rootView: editorView)

        let panel = FloatingPanel(contentView: hostingView)
        self.panel = panel
    }

    func setupHotKey() {
        hotKey = HotKey(key: .n, modifiers: [.option])
        hotKey?.keyDownHandler = { [weak self] in
            self?.togglePanel()
        }
    }

    func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let appState = self.appState,
                  let panel = self.panel,
                  panel.isVisible,
                  panel.isKeyWindow else {
                return event
            }

            let hasCmd = event.modifierFlags.contains(.command)

            // Current note delete confirmation
            if appState.confirmingDeleteCurrentNote {
                switch event.keyCode {
                case 36: // enter — confirm delete
                    if let note = appState.currentNote {
                        appState.confirmingDeleteCurrentNote = false
                        appState.deleteNote(note)
                        appState.showToast("Note deleted")
                    }
                    return nil
                case 53: // escape — cancel
                    appState.confirmingDeleteCurrentNote = false
                    return nil
                default:
                    return nil // eat all keys during confirmation
                }
            }

            // Escape to close shortcuts palette
            if appState.isShowingShortcuts && event.keyCode == 53 {
                appState.isShowingShortcuts = false
                return nil
            }

            // Browser-specific keys (no modifier needed)
            if appState.isShowingBrowser {
                // Delete confirmation mode
                if appState.confirmingDeleteNote != nil {
                    switch event.keyCode {
                    case 36: // return/enter — confirm delete
                        if let note = appState.confirmingDeleteNote {
                            appState.deleteNote(note)
                            appState.confirmingDeleteNote = nil
                            let notes = self.browserFilteredNotes()
                            if appState.browserSelectedIndex >= notes.count && appState.browserSelectedIndex > 0 {
                                appState.browserSelectedIndex = notes.count - 1
                            }
                        }
                        return nil
                    case 53: // escape — cancel delete
                        appState.confirmingDeleteNote = nil
                        return nil
                    default:
                        return nil // eat all other keys during confirmation
                    }
                }

                switch event.keyCode {
                case 126: // up arrow
                    appState.browserMoveUp()
                    return nil
                case 125: // down arrow
                    let notes = self.browserFilteredNotes()
                    appState.browserMoveDown(noteCount: notes.count)
                    return nil
                case 36: // return/enter
                    let notes = self.browserFilteredNotes()
                    appState.browserSelectCurrent(notes: notes)
                    return nil
                case 53: // escape
                    appState.isShowingBrowser = false
                    return nil
                default:
                    break
                }
            }

            // Ctrl+Cmd+Up/Down — move list item
            if hasCmd && event.modifierFlags.contains(.control) {
                if event.keyCode == 126 { // up arrow
                    self.evaluateJS("window.moveListItemBridge('up')")
                    return nil
                }
                if event.keyCode == 125 { // down arrow
                    self.evaluateJS("window.moveListItemBridge('down')")
                    return nil
                }
            }

            // Cmd+Shift+Enter — toggle to-do list
            if hasCmd && event.modifierFlags.contains(.shift) && event.keyCode == 36 {
                self.evaluateJS("toolbarAction('checkbox')")
                return nil
            }

            // Cmd shortcuts
            guard hasCmd else { return event }

            let key = event.charactersIgnoringModifiers ?? ""

            switch key {
            case "k":
                appState.isShowingBrowser = false
                appState.isShowingShortcuts.toggle()
                return nil
            case "p":
                appState.isShowingShortcuts = false
                appState.isShowingBrowser.toggle()
                if appState.isShowingBrowser {
                    appState.browserSelectedIndex = 0
                }
                return nil
            case "n":
                if !event.modifierFlags.contains(.shift) {
                    appState.createNewNote()
                    return nil
                }
                return event
            case "[":
                appState.navigateBack()
                return nil
            case "]":
                appState.navigateForward()
                return nil
            // Cmd+Shift+B — blockquote
            case "B":
                if event.modifierFlags.contains(.shift) {
                    self.evaluateJS("toolbarAction('blockquote')")
                    return nil
                }
                return event
            // Cmd+Shift+S — strikethrough
            case "S":
                if event.modifierFlags.contains(.shift) {
                    self.evaluateJS("toolbarAction('strike')")
                    return nil
                }
                return event
            case ")", "(", "'", "&", "*", "7", "8", "9":
                if event.modifierFlags.contains(.shift) {
                    switch event.keyCode {
                    case 26: // 7 key — toggle bullet list
                        self.evaluateJS("toolbarAction('bullet')")
                        return nil
                    case 28: // 8 key — toggle ordered list
                        self.evaluateJS("toolbarAction('ordered')")
                        return nil
                    default:
                        break
                    }
                }
                return event
            default:
                // Cmd+Option+C — toggle code block
                if event.modifierFlags.contains(.option) && event.keyCode == 8 {
                    self.evaluateJS("toolbarAction('codeblock')")
                    return nil
                }
                // cmd+backspace
                if event.keyCode == 51 {
                    if appState.isShowingBrowser {
                        let notes = self.browserFilteredNotes()
                        if appState.browserSelectedIndex < notes.count {
                            appState.confirmingDeleteNote = notes[appState.browserSelectedIndex]
                        }
                    } else if let note = appState.currentNote {
                        appState.confirmingDeleteCurrentNote = true
                    }
                    return nil
                }
                return event
            }
        }
    }

    private func evaluateJS(_ js: String) {
        if let panel = panel,
           let hostingView = panel.contentView,
           let webView = findWebView(in: hostingView) {
            webView.evaluateJavaScript(js)
        }
    }

    private func findWebView(in view: NSView) -> WKWebView? {
        if let wk = view as? WKWebView { return wk }
        for sub in view.subviews {
            if let found = findWebView(in: sub) { return found }
        }
        return nil
    }

    /// Compute filtered notes list matching NoteBrowser's logic
    private func browserFilteredNotes() -> [Note] {
        guard let appState = appState else { return [] }
        let notes = appState.noteStore.listNotes()
        let pinnedOrder = appState.pinnedFilenames
        let pinnedSet = appState.pinnedSet
        return notes.sorted { a, b in
            let aPinned = pinnedSet.contains(a.filename)
            let bPinned = pinnedSet.contains(b.filename)
            if aPinned != bPinned { return aPinned }
            if aPinned && bPinned {
                let aIdx = pinnedOrder.firstIndex(of: a.filename) ?? 0
                let bIdx = pinnedOrder.firstIndex(of: b.filename) ?? 0
                return aIdx < bIdx
            }
            return a.modifiedAt > b.modifiedAt
        }
    }

    func togglePanel() {
        if panel == nil {
            setupPanel()
        }
        // Dismiss browser overlay before hiding
        if panel?.isVisible == true {
            appState?.isShowingBrowser = false
        }
        panel?.toggle()
        if panel?.isVisible == true {
            appState?.loadInitialNote()
        }
    }

    func showPanel() {
        if panel == nil {
            setupPanel()
        }
        if panel?.isVisible != true {
            panel?.toggle()
        }
    }
}
