import Foundation

class NoteStore {
    let notesDirectory: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        notesDirectory = home.appendingPathComponent("Documents/Notes")

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: notesDirectory.path) {
            try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
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

    func deleteNote(_ filename: String) {
        let url = notesDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func extractTitle(content: String, filename: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Untitled"
        }
        // First line is the title, strip any markdown heading prefix
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

    private func slugify(_ text: String) -> String {
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
