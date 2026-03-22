import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let html = MarkdownRenderer.render(markdown, isDark: isDark)
            let htmlData = Data(html.utf8)

            guard let attrStr = NSAttributedString(html: htmlData, documentAttributes: nil) else {
                handler(NSError(domain: "MarkdownPreview", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "Failed to render HTML"]))
                return
            }

            let scrollView = NSScrollView(frame: view.bounds)
            scrollView.autoresizingMask = [.width, .height]
            scrollView.hasVerticalScroller = true
            scrollView.drawsBackground = true
            scrollView.backgroundColor = isDark ? NSColor(white: 0.12, alpha: 1) : .white
            scrollView.borderType = .noBorder

            let textView = NSTextView(frame: view.bounds)
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = true
            textView.backgroundColor = isDark ? NSColor(white: 0.12, alpha: 1) : .white
            textView.textContainerInset = NSSize(width: 28, height: 32)
            textView.textStorage?.setAttributedString(attrStr)

            scrollView.documentView = textView
            view.addSubview(scrollView)

            handler(nil)
        } catch {
            handler(error)
        }
    }
}

// MARK: - Markdown to HTML Renderer

struct MarkdownRenderer {

    static func render(_ markdown: String, isDark: Bool = false) -> String {
        if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let c = isDark ? "#7f7f7f" : "#9b9a97"
            return wrapInDocument("<p style=\"color:\(c);font-style:italic;\">Empty note</p>", isDark: isDark)
        }
        let body = convertToHTML(markdown, isDark: isDark)
        return wrapInDocument(body, isDark: isDark)
    }

    // MARK: Block-level parsing

    private enum ListType: Equatable {
        case none, unordered, ordered, task
    }

    private static func convertToHTML(_ markdown: String, isDark: Bool) -> String {
        let colors = isDark ? dark : light
        let lines = markdown.components(separatedBy: "\n")
        var html = ""
        var inCodeBlock = false
        var codeContent = ""
        var currentList = ListType.none

        func closeList() {
            switch currentList {
            case .none: break
            case .unordered, .task: html += "</ul>\n"
            case .ordered: break
            }
            currentList = .none
        }

        for line in lines {
            // --- Code fences ---
            if line.hasPrefix("```") {
                if inCodeBlock {
                    let trimmed = codeContent.hasSuffix("\n") ? String(codeContent.dropLast()) : codeContent
                    // Use a table cell for reliable background rendering in NSAttributedString
                    html += "<table width=\"100%\" cellpadding=\"16\" cellspacing=\"0\" style=\"margin:8px 0 16px 0;\"><tr>"
                    html += "<td style=\"background:\(colors.codeBg);font-family:Menlo,monospace;font-size:13px;line-height:1.6;color:\(colors.text);\">"
                    html += "<pre style=\"margin:0;\">\(escapeHTML(trimmed))</pre>"
                    html += "</td></tr></table>\n"
                    inCodeBlock = false
                    codeContent = ""
                } else {
                    closeList()
                    inCodeBlock = true
                    _ = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if inCodeBlock {
                codeContent += line + "\n"
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // --- Empty line ---
            if trimmed.isEmpty {
                closeList()
                continue
            }

            // --- Horizontal rule ---
            if trimmed.range(of: "^(-{3,}|\\*{3,}|_{3,})$", options: .regularExpression) != nil {
                closeList()
                html += "<hr style=\"border:none;border-top:1px solid \(colors.border);margin:28px 0;\">\n"
                continue
            }

            // --- Headings (use <br> spacer since NSAttributedString collapses margins) ---
            if let match = trimmed.range(of: "^(#{1,6})\\s+", options: .regularExpression) {
                closeList()
                let level = trimmed[match].filter { $0 == "#" }.count
                let content = String(trimmed[match.upperBound...])
                let sizes = ["30", "24", "20", "18", "16", "14"]
                let size = sizes[level - 1]
                // Add visible spacer before heading (except if it's the first element)
                if !html.isEmpty {
                    html += "<p style=\"font-size:8px;line-height:8px;\">&nbsp;</p>\n"
                }
                html += "<p style=\"font-size:\(size)px;font-weight:bold;margin-bottom:4px;\">\(processInline(content, colors: colors))</p>\n"
                continue
            }

            // --- Blockquote ---
            if trimmed.hasPrefix("> ") {
                closeList()
                let content = String(trimmed.dropFirst(2))
                html += "<p><span style=\"color:\(colors.border);font-size:22px;\">\u{258E}</span>&nbsp; \(processInline(content, colors: colors))</p>\n"
                continue
            }
            if trimmed == ">" {
                closeList()
                html += "<p><span style=\"color:\(colors.border);font-size:22px;\">\u{258E}</span></p>\n"
                continue
            }

            // --- Task list items ---
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                if currentList != .task { closeList(); html += "<ul style=\"list-style:none;padding-left:2px;margin:2px 0;\">\n"; currentList = .task }
                let content = String(trimmed.dropFirst(6))
                html += "<li style=\"margin-bottom:2px;font-weight:normal;color:\(colors.textSecondary);\"><span style=\"color:#2eaadc;\">\u{2611}</span> <s>\(processInline(content, colors: colors))</s></li>\n"
                continue
            }
            if trimmed.hasPrefix("- [ ] ") {
                if currentList != .task { closeList(); html += "<ul style=\"list-style:none;padding-left:2px;margin:2px 0;\">\n"; currentList = .task }
                let content = String(trimmed.dropFirst(6))
                html += "<li style=\"margin-bottom:2px;font-weight:normal;\">\u{2610} \(processInline(content, colors: colors))</li>\n"
                continue
            }

            // --- Unordered list ---
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if currentList != .unordered { closeList(); html += "<ul style=\"padding-left:28px;margin:4px 0;\">\n"; currentList = .unordered }
                let content = String(trimmed.dropFirst(2))
                html += "<li style=\"margin-bottom:4px;\">\(processInline(content, colors: colors))</li>\n"
                continue
            }

            // --- Ordered list (as paragraphs to avoid NSAttributedString grey markers) ---
            if let match = trimmed.range(of: "^(\\d+)\\.\\s+", options: .regularExpression) {
                if currentList != .ordered { closeList(); currentList = .ordered }
                let numMatch = trimmed.range(of: "^(\\d+)", options: .regularExpression)!
                let num = trimmed[numMatch]
                let content = String(trimmed[match.upperBound...])
                html += "<p style=\"margin-left:20px;margin-bottom:4px;\">\(num). \(processInline(content, colors: colors))</p>\n"
                continue
            }

            // --- Paragraph ---
            closeList()
            html += "<p style=\"margin-bottom:4px;\">\(processInline(trimmed, colors: colors))</p>\n"
        }

        // Close any open elements
        if inCodeBlock {
            html += "<table width=\"100%\" cellpadding=\"16\" cellspacing=\"0\" style=\"margin:8px 0 16px 0;\"><tr>"
            html += "<td style=\"background:\(colors.codeBg);font-family:Menlo,monospace;font-size:13px;line-height:1.6;color:\(colors.text);\">"
            html += "<pre style=\"margin:0;\">\(escapeHTML(codeContent))</pre>"
            html += "</td></tr></table>\n"
        }
        closeList()

        return html
    }

    // MARK: Inline formatting

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func processInline(_ text: String, colors: Colors) -> String {
        var s = escapeHTML(text)

        s = s.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\(([^)]+)\\)",
                                   with: "<img src=\"$2\" alt=\"$1\">", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]*)\\]\\(([^)]+)\\)",
                                   with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*\\*\\*(.+?)\\*\\*\\*",
                                   with: "<strong><em>$1</em></strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*",
                                   with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<![\\w\\*])\\*([^*]+?)\\*(?![\\w\\*])",
                                   with: "<em>$1</em>", options: .regularExpression)
        s = s.replacingOccurrences(of: "~~(.+?)~~",
                                   with: "<del>$1</del>", options: .regularExpression)
        // Inline code with colors baked in
        s = s.replacingOccurrences(of: "`([^`]+)`",
                                   with: "<code style=\"font-family:Menlo,monospace;font-size:13px;background:\(colors.codeBg);color:\(colors.accent);padding:2px 5px;\">$1</code>",
                                   options: .regularExpression)
        return s
    }

    // MARK: HTML wrapper

    private static func wrapInDocument(_ body: String, isDark: Bool) -> String {
        let colors = isDark ? dark : light
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body {
            font-family: -apple-system, 'Helvetica Neue', sans-serif;
            font-size: 16px;
            line-height: 1.7;
            color: \(colors.text);
        }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    // MARK: Colors

    private struct Colors {
        let text: String
        let textSecondary: String
        let accent: String
        let codeBg: String
        let border: String
    }

    private static let light = Colors(
        text: "#37352f",
        textSecondary: "#9b9a97",
        accent: "#eb5757",
        codeBg: "#f7f6f3",
        border: "#d4d4d4"
    )

    private static let dark = Colors(
        text: "#e6e3dd",
        textSecondary: "#7f7f7f",
        accent: "#ff7369",
        codeBg: "#252525",
        border: "#404040"
    )
}
