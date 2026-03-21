import Foundation

class NoteStore {
    let notesDirectory: URL
    let imagesDirectory: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        notesDirectory = home.appendingPathComponent("Documents/Notes")
        imagesDirectory = notesDirectory.appendingPathComponent("images")

        // Create directories if they don't exist
        for dir in [notesDirectory, imagesDirectory] {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    /// Save image data to the images directory. Returns the file URL.
    func saveImage(data: Data, mimeType: String) -> URL? {
        let ext: String
        switch mimeType {
        case "image/png": ext = "png"
        case "image/jpeg", "image/jpg": ext = "jpg"
        case "image/gif": ext = "gif"
        case "image/webp": ext = "webp"
        default: ext = "png"
        }

        let filename = "\(UUID().uuidString).\(ext)"
        let url = imagesDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url)
            return url
        } catch {
            print("[NoteStore] Failed to save image: \(error)")
            return nil
        }
    }

    func listNotes() -> [Note] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: notesDirectory.path) else {
            return []
        }

        let notes: [Note] = files
            .filter { $0.hasSuffix(".md") }
            .compactMap { filename in
                readNote(filename)
            }

        return notes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func readNote(_ filename: String) -> Note? {
        let url = notesDirectory.appendingPathComponent(filename)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let createdAt = (attrs?[.creationDate] as? Date) ?? Date()
        let modifiedAt = (attrs?[.modificationDate] as? Date) ?? Date()

        return Note(
            filename: filename,
            title: extractTitle(content: content, filename: filename),
            content: content,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }

    func saveNote(_ filename: String, content: String) {
        let url = notesDirectory.appendingPathComponent(filename)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func createNote(title: String = "Untitled") -> Note {
        let dateStr = Self.dateFormatter.string(from: Date())
        let slug = slugify(title)

        var filename = "\(dateStr)-\(slug).md"
        var counter = 1
        while FileManager.default.fileExists(atPath: notesDirectory.appendingPathComponent(filename).path) {
            filename = "\(dateStr)-\(slug)-\(counter).md"
            counter += 1
        }

        let content = ""
        let url = notesDirectory.appendingPathComponent(filename)
        try? content.write(to: url, atomically: true, encoding: .utf8)

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return Note(
            filename: filename,
            title: title,
            content: content,
            createdAt: (attrs?[.creationDate] as? Date) ?? Date(),
            modifiedAt: (attrs?[.modificationDate] as? Date) ?? Date()
        )
    }

    /// Rename a note file based on its new title. Returns the new filename, or the old one if no rename needed.
    func renameIfNeeded(_ filename: String, newTitle: String) -> String {
        let newSlug = slugify(newTitle.isEmpty ? "untitled" : newTitle)
        let oldSlug = extractSlug(from: filename)

        // No change needed
        if newSlug == oldSlug { return filename }

        // Preserve the date prefix if present
        let datePrefix: String
        if filename.count >= 10,
           filename[filename.index(filename.startIndex, offsetBy: 4)] == "-",
           filename[filename.index(filename.startIndex, offsetBy: 7)] == "-" {
            datePrefix = String(filename.prefix(10))
        } else {
            let dateStr = Self.dateFormatter.string(from: Date())
            datePrefix = dateStr
        }

        var newFilename = "\(datePrefix)-\(newSlug).md"
        // Avoid collisions
        var counter = 1
        while newFilename != filename && FileManager.default.fileExists(atPath: notesDirectory.appendingPathComponent(newFilename).path) {
            newFilename = "\(datePrefix)-\(newSlug)-\(counter).md"
            counter += 1
        }

        if newFilename == filename { return filename }

        let oldURL = notesDirectory.appendingPathComponent(filename)
        let newURL = notesDirectory.appendingPathComponent(newFilename)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            print("[NoteStore] Renamed \(filename) → \(newFilename)")
            return newFilename
        } catch {
            print("[NoteStore] Rename failed: \(error)")
            return filename
        }
    }

    func deleteNote(_ filename: String) {
        let url = notesDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    /// Extract the slug portion from a filename like "2026-03-20-my-title.md" → "my-title"
    private func extractSlug(from filename: String) -> String {
        var name = filename
        if name.hasSuffix(".md") { name = String(name.dropLast(3)) }
        // Remove date prefix (yyyy-MM-dd-)
        if name.count > 11,
           name[name.index(name.startIndex, offsetBy: 4)] == "-",
           name[name.index(name.startIndex, offsetBy: 7)] == "-",
           name[name.index(name.startIndex, offsetBy: 10)] == "-" {
            name = String(name.dropFirst(11))
        }
        // Remove trailing counter (-1, -2, etc.)
        if let lastDash = name.lastIndex(of: "-"),
           let suffix = Int(name[name.index(after: lastDash)...]) {
            name = String(name[..<lastDash])
        }
        return name
    }

    private func extractTitle(content: String, filename: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Untitled"
        }

        // Try parsing as JSON (TipTap editor format)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let contentArr = json["content"] as? [[String: Any]] {
            // Find first node with text content
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
        // Remove heading markers
        while firstLine.hasPrefix("#") {
            firstLine = String(firstLine.dropFirst())
        }
        firstLine = firstLine.trimmingCharacters(in: .whitespaces)
        if firstLine.isEmpty {
            return "Untitled"
        }
        // Character limit
        if firstLine.count > 60 {
            return String(firstLine.prefix(60)) + "…"
        }
        return firstLine
    }

    func slugify(_ text: String) -> String {
        let slug = text
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(slug.prefix(50))
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
