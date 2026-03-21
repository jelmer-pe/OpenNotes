import SwiftUI

struct NoteBrowser: View {
    @ObservedObject var appState: AppState
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var selectedIndex: Int {
        get { appState.browserSelectedIndex }
        nonmutating set { appState.browserSelectedIndex = newValue }
    }

    private var filteredNotes: [Note] {
        let notes = appState.noteStore.listNotes()
        let filtered: [Note]
        if searchText.isEmpty {
            filtered = notes
        } else {
            let query = searchText.lowercased()
            filtered = notes.filter {
                $0.title.lowercased().contains(query) ||
                $0.content.lowercased().contains(query)
            }
        }
        let pinnedOrder = appState.pinnedFilenames
        let pinnedSet = appState.pinnedSet
        return filtered.sorted { a, b in
            let aPinned = pinnedSet.contains(a.filename)
            let bPinned = pinnedSet.contains(b.filename)
            if aPinned != bPinned { return aPinned }
            if aPinned && bPinned {
                // Preserve insertion order for pinned notes
                let aIdx = pinnedOrder.firstIndex(of: a.filename) ?? 0
                let bIdx = pinnedOrder.firstIndex(of: b.filename) ?? 0
                return aIdx < bIdx
            }
            return a.modifiedAt > b.modifiedAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
                .padding(.horizontal, 12)
            if let note = appState.confirmingDeleteNote {
                deleteConfirmBar(note)
            } else {
                notesList
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .onAppear {
            isSearchFocused = true
            appState.browserSelectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if appState.confirmingDeleteNote != nil { return .ignored }
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if appState.confirmingDeleteNote != nil { return .ignored }
            if selectedIndex < filteredNotes.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            if appState.confirmingDeleteNote != nil {
                appState.confirmingDeleteNote = nil
                return .handled
            }
            appState.isShowingBrowser = false
            return .handled
        }
        .onKeyPress(.return) {
            if let note = appState.confirmingDeleteNote {
                appState.deleteNote(note)
                appState.confirmingDeleteNote = nil
                let notes = filteredNotes
                if selectedIndex >= notes.count && selectedIndex > 0 {
                    selectedIndex = notes.count - 1
                }
                return .handled
            }
            selectNote(at: selectedIndex)
            return .handled
        }
        .onChange(of: searchText) { _, _ in
            appState.browserSelectedIndex = 0
        }
        .onChange(of: appState.deleteRequested) { _, requested in
            if requested {
                appState.deleteRequested = false
                let notes = filteredNotes
                if selectedIndex < notes.count {
                    appState.confirmingDeleteNote = notes[selectedIndex]
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            TextField("Search notes…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                .onSubmit {
                    selectNote(at: selectedIndex)
                }
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 11)
    }

    private func deleteConfirmBar(_ note: Note) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Delete \"\(note.title)\"?")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 10) {
                Button("Cancel") {
                    appState.confirmingDeleteNote = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 19)
                .padding(.vertical, 6)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button("Delete") {
                    appState.deleteNote(note)
                    appState.confirmingDeleteNote = nil
                    let notes = filteredNotes
                    if selectedIndex >= notes.count && selectedIndex > 0 {
                        selectedIndex = notes.count - 1
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 19)
                .padding(.vertical, 6)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text("Press Enter to confirm · Esc to cancel")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var notesList: some View {
        let pinned = filteredNotes.filter { appState.isPinned($0) }
        let unpinned = filteredNotes.filter { !appState.isPinned($0) }

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if !pinned.isEmpty {
                        pinnedSection(pinned)
                    }
                    if !pinned.isEmpty && !unpinned.isEmpty {
                        Divider()
                            .padding(.horizontal, 19)
                            .padding(.vertical, 6)
                    }
                    unpinnedSection(unpinned, offset: pinned.count)
                }
                .padding(.vertical, 6)
            }
            .onChange(of: selectedIndex) { _, newValue in
                let notes = filteredNotes
                if newValue < notes.count {
                    proxy.scrollTo(notes[newValue].id, anchor: .center)
                }
            }
        }
    }

    private func pinnedSection(_ notes: [Note]) -> some View {
        Group {
            Text("Pinned")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.7))
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 19)
                .padding(.top, 8)
                .padding(.bottom, 2)

            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                noteRow(note: note, globalIndex: index)
            }
        }
    }

    private func unpinnedSection(_ notes: [Note], offset: Int) -> some View {
        ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
            noteRow(note: note, globalIndex: offset + index)
        }
    }

    private func noteRow(note: Note, globalIndex: Int) -> some View {
        NoteRow(
            note: note,
            isCurrent: note.filename == appState.currentNote?.filename,
            isSelected: globalIndex == selectedIndex,
            isPinned: appState.isPinned(note),
            onSelect: { appState.openNote(note) },
            onHover: { appState.browserSelectedIndex = globalIndex },
            onDelete: { appState.confirmingDeleteNote = note },
            onTogglePin: { appState.togglePin(note) }
        )
        .id(note.id)
    }

    private func selectNote(at index: Int) {
        let notes = filteredNotes
        if index < notes.count {
            appState.openNote(notes[index])
        }
    }
}

struct NoteRow: View {
    let note: Note
    let isCurrent: Bool
    let isSelected: Bool
    let isPinned: Bool
    let onSelect: () -> Void
    let onHover: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            noteInfo
            Spacer(minLength: 8)
            if isSelected {
                actionButtons
            }
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.primary.opacity(0.06) : Color.clear)
                .padding(.horizontal, 11)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            if hovering { onHover() }
        }
    }

    private var noteInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 5) {
                if isCurrent {
                    Circle().fill(Color.red).frame(width: 5, height: 5)
                    Text("Current")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                    Text("·")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                Text(relativeTime(note.modifiedAt))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("·")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary.opacity(0.5))
                Text(formatCharCount(note.content.count))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 { return "Just now" }
        if interval < 3600 {
            let mins = Int(interval / 60)
            return mins == 1 ? "1 min ago" : "\(mins) mins ago"
        }
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0

        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days) days ago" }
        if days < 30 {
            let weeks = days / 7
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        }
        if days < 365 {
            let months = days / 30
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }
        let years = days / 365
        return years == 1 ? "1 year ago" : "\(years) years ago"
    }

    private func formatCharCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk chars", Double(count) / 1000.0)
        }
        return "\(count) chars"
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
