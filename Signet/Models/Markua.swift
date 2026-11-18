import Foundation

/// Turns a chapter of the Signet book (Leanpub's Markua, the subset the book uses) into HTML for
/// Help > Getting Started: `{#id: …}` anchors, `#` headings, paragraphs, `-`/`*`/`1.` lists,
/// `|` tables, fenced code, `![](path)` images, `A>`/`I>`/`W>`/`T>` asides, and inline links,
/// code, bold and italics. Every piece of text is HTML-escaped; links to a chapter that is not
/// in this one go to the book on Leanpub.
enum Markua {
    /// Where the book is read online; a `#id` link to another chapter goes to `bookURL/<id>`.
    static let bookURL = "https://leanpub.com/read/tezossignet"

    static func html(from source: String, title: String) -> String {
        let lines = withoutComments(source.replacingOccurrences(of: "\r\n", with: "\n")).components(separatedBy: "\n")
        let anchors = Set(lines.compactMap(anchor(in:)))
        var body = ""
        var paragraph: [String] = []
        var pendingAnchor: String?
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            body += "<p>\(inline(paragraph.joined(separator: " "), anchors: anchors))</p>\n"
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let id = anchor(in: line) {
                flushParagraph()
                pendingAnchor = id
                index += 1
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }
            // Fenced code: everything up to the closing fence, as is.
            if trimmed.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                body += "<pre><code>\(escape(code.joined(separator: "\n")))</code></pre>\n"
                continue
            }
            if let (level, text) = heading(trimmed) {
                flushParagraph()
                let id = pendingAnchor.map { " id=\"\(escape($0))\"" } ?? ""
                pendingAnchor = nil
                body += "<h\(level)\(id)>\(inline(text, anchors: anchors))</h\(level)>\n"
                index += 1
                continue
            }
            if let image = image(trimmed) {
                flushParagraph()
                body += "<figure><img src=\"\(escape(image.path))\" alt=\"\(escape(image.alt))\">"
                    + (image.alt.isEmpty ? "" : "<figcaption>\(escape(image.alt))</figcaption>") + "</figure>\n"
                index += 1
                continue
            }
            if trimmed.hasPrefix("|") {
                flushParagraph()
                var rows: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                body += table(rows, anchors: anchors)
                continue
            }
            if let kind = aside(trimmed) {
                flushParagraph()
                var text: [String] = []
                while index < lines.count, let rest = asideText(lines[index].trimmingCharacters(in: .whitespaces), kind: kind) {
                    text.append(rest)
                    index += 1
                }
                body += "<aside class=\"\(kind)\"><p>\(inline(text.joined(separator: " "), anchors: anchors))</p></aside>\n"
                continue
            }
            if listItem(trimmed) != nil {
                flushParagraph()
                let ordered = listItem(trimmed)!.ordered
                var items: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if let item = listItem(current) {
                        items.append(item.text)
                    } else if !current.isEmpty, !items.isEmpty, lines[index].hasPrefix(" ") {
                        items[items.count - 1] += " " + current  // a wrapped item
                    } else {
                        break
                    }
                    index += 1
                }
                let tag = ordered ? "ol" : "ul"
                body += "<\(tag)>" + items.map { "<li>\(inline($0, anchors: anchors))</li>" }.joined() + "</\(tag)>\n"
                continue
            }
            paragraph.append(trimmed)
            index += 1
        }
        flushParagraph()
        return page(title: title, body: body)
    }

    /// The text without `<!-- … -->` comments, the author's notes Leanpub does not print; an
    /// unclosed comment runs to the end.
    static func withoutComments(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let start = rest.range(of: "<!--") {
            out += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].range(of: "-->") else { return out }
            rest = rest[end.upperBound...]
        }
        return out + rest
    }

    // MARK: Blocks

    static func anchor(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{#id:"), trimmed.hasSuffix("}") else { return nil }
        let id = trimmed.dropFirst(5).dropLast().trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func image(_ line: String) -> (alt: String, path: String)? {
        guard line.hasPrefix("!["), line.hasSuffix(")"), let close = line.range(of: "](") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
        let path = String(line[close.upperBound..<line.index(before: line.endIndex)])
        // Only pictures shipped beside the chapter: no other files, no other sites.
        guard !path.contains(".."), !path.contains(":"), !path.hasPrefix("/") else { return nil }
        return (alt, path)
    }

    private static func aside(_ line: String) -> String? {
        for (marker, kind) in [("A>", "aside"), ("I>", "info"), ("W>", "warning"), ("T>", "tip")] where line.hasPrefix(marker) { return kind }
        return nil
    }

    private static func asideText(_ line: String, kind: String) -> String? {
        guard aside(line) == kind else { return nil }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return (false, String(line.dropFirst(2))) }
        let digits = line.prefix(while: \.isNumber)
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") { return (true, String(line.dropFirst(digits.count + 2))) }
        return nil
    }

    private static func table(_ rows: [String], anchors: Set<String>) -> String {
        func cells(_ row: String) -> [String] {
            var inner = row
            if inner.hasPrefix("|") { inner.removeFirst() }
            if inner.hasSuffix("|") { inner.removeLast() }
            return inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let isSeparator = { (row: String) in cells(row).allSatisfy { !$0.isEmpty && $0.allSatisfy { "-:".contains($0) } } }
        var html = "<table>"
        var header = true
        if rows.count < 2 || !isSeparator(rows[1]) { header = false }
        for (i, row) in rows.enumerated() where !isSeparator(row) {
            let tag = header && i == 0 ? "th" : "td"
            html += "<tr>" + cells(row).map { "<\(tag)>\(inline($0, anchors: anchors))</\(tag)>" }.joined() + "</tr>"
        }
        return html + "</table>\n"
    }

    // MARK: Inline

    /// Links, code, bold and italics in a line of text, escaped.
    static func inline(_ text: String, anchors: Set<String>) -> String {
        var out = ""
        var rest = Substring(text)
        while let next = rest.firstIndex(where: { "`[*_".contains($0) }) {
            out += escape(String(rest[..<next]))
            rest = rest[next...]
            if rest.hasPrefix("`"), let end = rest.dropFirst().firstIndex(of: "`") {
                out += "<code>\(escape(String(rest[rest.index(after: rest.startIndex)..<end])))</code>"
                rest = rest[rest.index(after: end)...]
            } else if rest.hasPrefix("["), let close = rest.range(of: "]("), let end = rest[close.upperBound...].firstIndex(of: ")") {
                let label = String(rest[rest.index(after: rest.startIndex)..<close.lowerBound])
                let target = String(rest[close.upperBound..<end])
                out += link(label: label, target: target, anchors: anchors)
                rest = rest[rest.index(after: end)...]
            } else if rest.hasPrefix("**"), let end = rest.dropFirst(2).range(of: "**") {
                out += "<strong>\(inline(String(rest[rest.index(rest.startIndex, offsetBy: 2)..<end.lowerBound]), anchors: anchors))</strong>"
                rest = rest[end.upperBound...]
            } else if let mark = rest.first, mark == "*" || mark == "_", let end = rest.dropFirst().firstIndex(of: mark),
                      end > rest.index(after: rest.startIndex), !(mark == "_" && isWordCharacter(before: rest.startIndex, in: text, rest: rest)) {
                out += "<em>\(escape(String(rest[rest.index(after: rest.startIndex)..<end])))</em>"
                rest = rest[rest.index(after: end)...]
            } else {
                out += escape(String(rest.prefix(1)))
                rest = rest.dropFirst()
            }
        }
        return out + escape(String(rest))
    }

    /// Underscores inside words (snake_case) are not emphasis.
    private static func isWordCharacter(before index: Substring.Index, in text: String, rest: Substring) -> Bool {
        let offset = text.distance(from: text.startIndex, to: index)
        guard offset > 0 else { return false }
        let previous = text[text.index(text.startIndex, offsetBy: offset - 1)]
        return previous.isLetter || previous.isNumber
    }

    private static func link(label: String, target: String, anchors: Set<String>) -> String {
        let href: String
        if target.hasPrefix("#") {
            let id = String(target.dropFirst())
            href = anchors.contains(id) ? "#\(id)" : "\(bookURL)/\(id)"
        } else if target.hasPrefix("https://") || target.hasPrefix("http://") || target.hasPrefix("mailto:") {
            href = target
        } else {
            return escape(label)
        }
        return "<a href=\"\(escape(href))\">\(inline(label, anchors: anchors))</a>"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: Page

    private static func page(title: String, body: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file:; style-src 'unsafe-inline'">
        <title>\(escape(title))</title>
        <style>
        :root { color-scheme: light dark; --text: #1d1d1f; --muted: #6e6e73; --rule: #d2d2d7; --code: #f5f5f7; --link: #0066cc; --aside: #f2f7ff; }
        @media (prefers-color-scheme: dark) { :root { --text: #f5f5f7; --muted: #a1a1a6; --rule: #424245; --code: #2c2c2e; --link: #4da3ff; --aside: #1c2633; } }
        body { font: 15px/1.55 -apple-system, system-ui, sans-serif; color: var(--text); background: Canvas; margin: 0; }
        main { max-width: 760px; margin: 0 auto; padding: 28px 32px 48px; }
        h1 { font-size: 28px; margin: 0 0 12px; } h2 { font-size: 21px; margin-top: 32px; border-bottom: 1px solid var(--rule); padding-bottom: 4px; } h3 { font-size: 17px; margin-top: 24px; }
        a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
        code { font: 13px ui-monospace, Menlo, monospace; background: var(--code); padding: 1px 4px; border-radius: 4px; }
        pre { background: var(--code); padding: 12px 14px; border-radius: 8px; overflow-x: auto; } pre code { padding: 0; background: none; }
        figure { margin: 18px 0; text-align: center; } img { max-width: 100%; border-radius: 6px; box-shadow: 0 1px 6px rgba(0,0,0,.18); }
        figcaption { color: var(--muted); font-size: 13px; margin-top: 6px; }
        table { border-collapse: collapse; margin: 14px 0; font-size: 14px; } th, td { border: 1px solid var(--rule); padding: 6px 10px; text-align: left; }
        aside { background: var(--aside); border-left: 3px solid var(--link); padding: 2px 14px; border-radius: 4px; margin: 14px 0; }
        aside.warning { border-left-color: #e8a33d; }
        </style></head>
        <body><main>
        \(body)
        </main></body></html>
        """
    }
}
