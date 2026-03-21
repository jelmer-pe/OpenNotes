import SwiftUI
import WebKit

struct EditorWebView: NSViewRepresentable {
    @ObservedObject var appState: AppState

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "bridge")
        config.userContentController = contentController

        // Allow file access for local resources
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        // Load editor HTML from bundle resources
        if let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Resources") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            // Fallback: try finding in the app's resource directory
            let resourcePath = Bundle.main.resourcePath ?? ""
            let htmlPath = (resourcePath as NSString).appendingPathComponent("editor.html")
            let htmlURL = URL(fileURLWithPath: htmlPath)
            if FileManager.default.fileExists(atPath: htmlPath) {
                webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
            }
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // When the current note changes, load its content
        if let note = appState.currentNote,
           note.filename != context.coordinator.loadedFilename {
            // If this is just a rename (same content), update the tracked filename without reloading
            if let loaded = context.coordinator.loadedFilename,
               note.content == context.coordinator.lastContent {
                context.coordinator.loadedFilename = note.filename
            } else {
                context.coordinator.loadNote(note)
            }
        }

        // Sync dimmed state with hover
        let shouldDim = !appState.isHovering
        if shouldDim != context.coordinator.isDimmed {
            context.coordinator.isDimmed = shouldDim
            webView.evaluateJavaScript("setDimmed(\(shouldDim))")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var appState: AppState
        var webView: WKWebView?
        var loadedFilename: String?
        var lastContent: String?
        var isDimmed = false
        private var isReady = false
        private var pendingNote: Note?

        init(appState: AppState) {
            self.appState = appState
        }

        func loadNote(_ note: Note) {
            if isReady {
                let escaped = note.content
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")

                webView?.evaluateJavaScript("loadContent(`\(escaped)`)")
                loadedFilename = note.filename
                lastContent = note.content
            } else {
                pendingNote = note
            }
        }

        func focusEditor() {
            webView?.evaluateJavaScript("focusEditor()")
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { return }

            DispatchQueue.main.async { [weak self] in
                switch type {
                case "ready":
                    self?.isReady = true
                    if let note = self?.pendingNote ?? self?.appState.currentNote {
                        self?.loadNote(note)
                    }
                    self?.focusEditor()

                case "contentChanged":
                    if let jsonStr = json["json"] as? String {
                        self?.lastContent = jsonStr
                        self?.appState.contentChanged(jsonStr)
                    }


                default:
                    break
                }
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Editor HTML loaded, wait for 'ready' message from JS
        }

    }
}
