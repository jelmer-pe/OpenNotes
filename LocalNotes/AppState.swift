import Foundation
import Combine

class AppState: ObservableObject {
    @Published var currentNote: Note?
    @Published var isShowingBrowser: Bool = false
    @Published var isPanelVisible: Bool = false
    @Published var deleteRequested: Bool = false
    @Published var toastMessage: String?
    @Published var isHovering: Bool = true
    @Published var isShowingShortcuts: Bool = false
    @Published var confirmingDeleteCurrentNote: Bool = false
    @Published var isShowingOnboarding: Bool = false

    let noteStore = NoteStore()

    // Navigation history
    private var historyBack: [String] = []
    private var historyForward: [String] = []

    // Auto-save
    private var saveTimer: Timer?
    private var pendingContent: String?

    // Last opened note persistence
    var lastOpenedFilename: String? {
        get { UserDefaults.standard.string(forKey: "lastOpenedNote") }
        set { UserDefaults.standard.set(newValue, forKey: "lastOpenedNote") }
    }

    // Pinned notes (ordered array to preserve insertion order)
    var pinnedFilenames: [String] {
        get { UserDefaults.standard.stringArray(forKey: "pinnedNotes") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "pinnedNotes") }
    }

    var pinnedSet: Set<String> {
        Set(pinnedFilenames)
    }

    func togglePin(_ note: Note) {
        var pinned = pinnedFilenames
        if let idx = pinned.firstIndex(of: note.filename) {
            pinned.remove(at: idx)
        } else {
            pinned.append(note.filename) // append = bottom of pinned list
        }
        pinnedFilenames = pinned
        objectWillChange.send()
    }

    func isPinned(_ note: Note) -> Bool {
        pinnedFilenames.contains(note.filename)
    }

    // Browser navigation state
    @Published var browserSelectedIndex = 0
    @Published var confirmingDeleteNote: Note?

    private static let onboardingKey = "hasCompletedOnboarding"

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardingKey) }
    }

    init() {
        loadInitialNote()
        if !UserDefaults.standard.bool(forKey: Self.onboardingKey) {
            isShowingOnboarding = true
        }
    }

    func dismissOnboarding() {
        isShowingOnboarding = false
        hasCompletedOnboarding = true
    }

    func loadInitialNote() {
        if let filename = lastOpenedFilename, let note = noteStore.readNote(filename) {
            currentNote = note
            return
        }

        let notes = noteStore.listNotes()
        if let first = notes.first {
            currentNote = first
            lastOpenedFilename = first.filename
        } else {
            let note = noteStore.createNote()
            currentNote = note
            lastOpenedFilename = note.filename
        }
    }

    func openNote(_ note: Note) {
        flushSave()

        // Push current note to back history
        if let current = currentNote {
            historyBack.append(current.filename)
            historyForward.removeAll()
        }

        currentNote = note
        lastOpenedFilename = note.filename
        isShowingBrowser = false
    }

    func createNewNote() {
        flushSave()

        if let current = currentNote {
            historyBack.append(current.filename)
            historyForward.removeAll()
        }

        let note = noteStore.createNote()
        currentNote = note
        lastOpenedFilename = note.filename
        showToast("New note created")
    }

    func navigateBack() {
        guard let filename = historyBack.popLast(),
              let note = noteStore.readNote(filename) else { return }

        flushSave()

        if let current = currentNote {
            historyForward.append(current.filename)
        }

        currentNote = note
        lastOpenedFilename = note.filename
    }

    func navigateForward() {
        guard let filename = historyForward.popLast(),
              let note = noteStore.readNote(filename) else { return }

        flushSave()

        if let current = currentNote {
            historyBack.append(current.filename)
        }

        currentNote = note
        lastOpenedFilename = note.filename
    }

    func contentChanged(_ markdown: String) {
        pendingContent = markdown

        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.flushSave()
        }
    }

    func flushSave() {
        guard let content = pendingContent, let filename = currentNote?.filename else { return }
        // Update the in-memory note
        let newTitle = extractTitle(content)
        currentNote?.content = content
        currentNote?.title = newTitle
        currentNote?.modifiedAt = Date()

        // Rename file to match title, then save to the correct filename
        let newFilename = noteStore.renameIfNeeded(filename, newTitle: newTitle)
        if newFilename != filename {
            updateFilenameReferences(from: filename, to: newFilename)
        }
        noteStore.saveNote(newFilename, content: content)

        pendingContent = nil
        saveTimer?.invalidate()
    }

    /// Update all stored references when a note file is renamed
    private func updateFilenameReferences(from oldFilename: String, to newFilename: String) {
        currentNote?.filename = newFilename
        lastOpenedFilename = newFilename

        // Update navigation history
        historyBack = historyBack.map { $0 == oldFilename ? newFilename : $0 }
        historyForward = historyForward.map { $0 == oldFilename ? newFilename : $0 }

        // Update pinned notes
        var pinned = pinnedFilenames
        if let idx = pinned.firstIndex(of: oldFilename) {
            pinned[idx] = newFilename
            pinnedFilenames = pinned
        }
    }

    func deleteNote(_ note: Note) {
        noteStore.deleteNote(note.filename)

        if note.filename == currentNote?.filename {
            let notes = noteStore.listNotes()
            if let first = notes.first {
                currentNote = first
                lastOpenedFilename = first.filename
            } else {
                let newNote = noteStore.createNote()
                currentNote = newNote
                lastOpenedFilename = newNote.filename
            }
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

    func browserMoveUp() {
        if browserSelectedIndex > 0 {
            browserSelectedIndex -= 1
        }
    }

    func browserMoveDown(noteCount: Int) {
        if browserSelectedIndex < noteCount - 1 {
            browserSelectedIndex += 1
        }
    }

    func browserSelectCurrent(notes: [Note]) {
        if browserSelectedIndex < notes.count {
            openNote(notes[browserSelectedIndex])
        }
    }

    func requestDeleteSelectedNote() {
        if isShowingBrowser {
            deleteRequested = true
        }
    }

    private func extractTitle(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled" }

        // Try parsing as JSON (TipTap editor format)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let contentArr = json["content"] as? [[String: Any]] {
            for node in contentArr {
                if let nodeContent = node["content"] as? [[String: Any]] {
                    for inline in nodeContent {
                        if let text = inline["text"] as? String {
                            let title = text.trimmingCharacters(in: .whitespaces)
                            if !title.isEmpty {
                                return title.count > 60 ? String(title.prefix(60)) + "…" : title
                            }
                        }
                    }
                }
            }
            return "Untitled"
        }

        // Markdown format (backward compat)
        var firstLine = trimmed.components(separatedBy: "\n").first ?? ""
        while firstLine.hasPrefix("#") { firstLine = String(firstLine.dropFirst()) }
        firstLine = firstLine.trimmingCharacters(in: .whitespaces)
        if firstLine.isEmpty { return "Untitled" }
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
    }
}
