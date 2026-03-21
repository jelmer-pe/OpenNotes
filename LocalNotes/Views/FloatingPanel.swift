import AppKit
import SwiftUI

class FloatingPanel: NSPanel, NSWindowDelegate {
    private var previousApp: NSRunningApplication?
    private let minWidth: CGFloat = 400
    private let maxWidth: CGFloat = 800
    private let minHeight: CGFloat = 360
    private let maxHeight: CGFloat = 1200

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.delegate = self
        self.contentView = contentView
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.animationBehavior = .utilityWindow
        self.backgroundColor = .windowBackgroundColor
        self.titlebarSeparatorStyle = .none
        self.minSize = NSSize(width: minWidth, height: minHeight)
        self.maxSize = NSSize(width: maxWidth, height: maxHeight)

        if let frame = UserDefaults.standard.string(forKey: "panelFrame") {
            self.setFrame(NSRectFromString(frame), display: true)
        } else {
            self.center()
        }
    }

    override func close() {
        savePosition()
        dismissPanel()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func toggle() {
        if isVisible {
            savePosition()
            dismissPanel()
        } else {
            // Remember which app was active before we take focus
            previousApp = NSWorkspace.shared.frontmostApplication

            if let frame = UserDefaults.standard.string(forKey: "panelFrame") {
                setFrame(NSRectFromString(frame), display: true)
            }
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        var size = frameSize
        size.width = max(minWidth, min(maxWidth, size.width))
        size.height = max(minHeight, min(maxHeight, size.height))
        return size
    }

    func setTrafficLightsVisible(_ visible: Bool) {
        guard let buttons = contentView?.superview?.subviews.compactMap({ $0 as? NSButton }),
              !buttons.isEmpty else {
            // Fallback: use standardWindowButton
            for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                standardWindowButton(buttonType)?.animator().alphaValue = visible ? 1 : 0
            }
            return
        }
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(buttonType)?.animator().alphaValue = visible ? 1 : 0
        }
    }

    // MARK: - Private

    private func savePosition() {
        UserDefaults.standard.set(NSStringFromRect(self.frame), forKey: "panelFrame")
    }

    private func dismissPanel() {
        orderOut(nil)
        // Return focus to the app that was active before we showed
        if let app = previousApp, app != NSRunningApplication.current {
            app.activate()
        }
        previousApp = nil
    }
}
