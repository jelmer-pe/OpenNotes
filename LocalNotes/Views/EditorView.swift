import SwiftUI

struct EditorView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            // Main editor
            EditorWebView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Title bar (always present, contents dim on hover-out)
            VStack(spacing: 0) {
                titleBar
                Spacer()
            }

            // Toast
            if let message = appState.toastMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        .padding(.bottom, 52)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.2), value: appState.toastMessage != nil)
            }

            // Shortcuts palette
            if appState.isShowingShortcuts {
                Color.black.opacity(0.001)
                    .onTapGesture { appState.isShowingShortcuts = false }

                VStack {
                    ShortcutsPalette(appState: appState)
                        .padding(.top, 40)
                        .padding(.horizontal, 24)
                    Spacer()
                }
            }

            // Delete current note confirmation
            if appState.confirmingDeleteCurrentNote {
                Color.black.opacity(0.001)
                    .onTapGesture { appState.confirmingDeleteCurrentNote = false }

                VStack {
                    Spacer()
                    deleteCurrentNoteBar
                    Spacer()
                }
            }

            // Note browser overlay
            if appState.isShowingBrowser {
                Color.black.opacity(0.001)
                    .onTapGesture {
                        appState.isShowingBrowser = false
                    }

                VStack {
                    NoteBrowser(appState: appState)
                        .padding(.top, 40)
                        .padding(.horizontal, 24)
                    Spacer()
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.isHovering = hovering
            }
            // Hide/show traffic lights
            if let panel = NSApp.windows.first(where: { $0 is FloatingPanel }) as? FloatingPanel {
                panel.setTrafficLightsVisible(hovering)
            }
        }
    }

    private var titleBar: some View {
        ZStack {
            // Centered title
            Text(appState.currentNote?.title ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 80)
                .opacity(appState.isHovering ? 1 : 0.3)

            // Right-aligned buttons
            HStack(spacing: 2) {
                Spacer()

                TitleBarButton(icon: "doc.text.magnifyingglass", tooltip: "Browse Notes", shortcut: "⌘P") {
                    appState.isShowingShortcuts = false
                    appState.isShowingBrowser.toggle()
                    if appState.isShowingBrowser {
                        appState.browserSelectedIndex = 0
                    }
                }

                TitleBarButton(icon: "command", tooltip: "Shortcuts", shortcut: "⌘K") {
                    appState.isShowingBrowser = false
                    appState.isShowingShortcuts.toggle()
                }
            }
            .padding(.trailing, 10)
            .opacity(appState.isHovering ? 1 : 0.15)
        }
        .animation(.easeInOut(duration: 0.15), value: appState.isHovering)
        .frame(height: 28)
        .background(.ultraThinMaterial)
    }

    private var deleteCurrentNoteBar: some View {
        VStack(spacing: 12) {
            Text("Delete \"\(appState.currentNote?.title ?? "")\"?")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 10) {
                Button("Cancel") {
                    appState.confirmingDeleteCurrentNote = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button("Delete") {
                    if let note = appState.currentNote {
                        appState.confirmingDeleteCurrentNote = false
                        appState.deleteNote(note)
                        appState.showToast("Note deleted")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text("Press Enter to confirm · Esc to cancel")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
    }
}

struct TitleBarButton: View {
    let icon: String
    let tooltip: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                HStack(spacing: 4) {
                    Text(tooltip)
                        .font(.system(size: 11, weight: .medium))
                    ForEach(shortcut.map(String.init), id: \.self) { key in
                        Text(key)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(white: 0.16, opacity: 0.85))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .offset(y: 32)
                .fixedSize()
                .transition(.opacity)
            }
        }
    }
}

struct ShortcutsPalette: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ForEach(shortcutItems.indices, id: \.self) { index in
                let item = shortcutItems[index]
                if item.label == "---" {
                    Divider()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                } else {
                    shortcutRow(item)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
    }

    private var shortcutItems: [(icon: String, label: String, keys: String)] {
        [
            ("plus", "New Note", "⌘ N"),
            ("doc.text.magnifyingglass", "Browse Notes", "⌘ P"),
            ("trash", "Delete Note", "⌘ ⌫"),
            ("---", "---", ""),
            ("chevron.left", "Go Back", "⌘ ["),
            ("chevron.right", "Go Forward", "⌘ ]"),
            ("---", "---", ""),
            ("pin", "Pin / Unpin", "hover"),
            ("checkmark.square", "Toggle Checkbox", "⌘ ↵"),
            ("arrow.uturn.backward", "Undo", "⌘ Z"),
            ("arrow.uturn.forward", "Redo", "⇧ ⌘ Z"),
        ]
    }

    private func shortcutRow(_ item: (icon: String, label: String, keys: String)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(item.label)
                .font(.system(size: 12))

            Spacer()

            HStack(spacing: 3) {
                ForEach(item.keys.components(separatedBy: " "), id: \.self) { key in
                    Text(key)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 7)
    }
}
