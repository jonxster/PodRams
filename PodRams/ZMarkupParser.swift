import Foundation
#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

/// Lightweight renderer that turns Markdown/HTML show notes into themed attributed strings.
/// Inspired by the open-source ZMarkupParser project to provide readable, styled notes.
final class ZMarkupParser {
    /// Shared parser instance reused across the app so cache usage stays centralized.
    static let shared = ZMarkupParser()

    /// Styling tokens for rendered output.
    struct Theme {
        let bodyFont: PlatformFont
        let boldFont: PlatformFont
        let italicFont: PlatformFont
        let monospacedFont: PlatformFont
        let headingFonts: [Int: PlatformFont]
        let linkColor: PlatformColor
        let listBullet: String
        let listIndent: CGFloat
        let listMarkerSpacing: CGFloat
        let lineSpacing: CGFloat
        let paragraphSpacing: CGFloat
        let blockquoteIndicator: String
        let blockquoteIndicatorColor: PlatformColor
        let blockquoteTextColor: PlatformColor
        let blockquoteIndent: CGFloat
        let codeBackgroundColor: PlatformColor
        let codeTextColor: PlatformColor
        let codeCornerRadius: CGFloat
        let codeParagraphSpacing: CGFloat
        let horizontalRuleString: String

        static var podramsDefault: Theme {
            #if os(macOS)
            let body = NSFont.preferredFont(forTextStyle: .body)
            let bold = NSFontManager.shared.convert(body, toHaveTrait: .boldFontMask)
            let italicCandidate = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
            let italic = italicCandidate.fontName == body.fontName ? body : italicCandidate
            let mono = NSFont.monospacedSystemFont(ofSize: max(11, body.pointSize - 1), weight: .regular)
            let heading1 = NSFont.preferredFont(forTextStyle: .title2)
            let heading2 = NSFont.preferredFont(forTextStyle: .title3)
            let heading3 = NSFont.systemFont(ofSize: body.pointSize + 2, weight: .semibold)
            let heading4 = NSFont.systemFont(ofSize: body.pointSize + 1, weight: .semibold)
            let heading5 = NSFont.systemFont(ofSize: body.pointSize, weight: .semibold)
            let heading6 = NSFont.systemFont(ofSize: body.pointSize, weight: .medium)
            let headings: [Int: NSFont] = [
                1: heading1,
                2: heading2,
                3: heading3,
                4: heading4,
                5: heading5,
                6: heading6
            ]
            let linkColor = NSColor.linkColor
            let indicatorColor = NSColor.separatorColor
            let quoteTextColor = NSColor.labelColor.withAlphaComponent(0.85)
            let codeBackground = NSColor.textBackgroundColor.withAlphaComponent(0.9)
            let codeText = NSColor.labelColor
            return Theme(
                bodyFont: body,
                boldFont: bold,
                italicFont: italic,
                monospacedFont: mono,
                headingFonts: headings,
                linkColor: linkColor,
                listBullet: "•",
                listIndent: 22,
                listMarkerSpacing: 6,
                lineSpacing: 4,
                paragraphSpacing: 10,
                blockquoteIndicator: "▎",
                blockquoteIndicatorColor: indicatorColor,
                blockquoteTextColor: quoteTextColor,
                blockquoteIndent: 14,
                codeBackgroundColor: codeBackground,
                codeTextColor: codeText,
                codeCornerRadius: 4,
                codeParagraphSpacing: 8,
                horizontalRuleString: "────────────"
            )
            #else
            let body = UIFont.preferredFont(forTextStyle: .body)
            let bold = UIFont(descriptor: body.fontDescriptor.withSymbolicTraits(.traitBold) ?? body.fontDescriptor, size: body.pointSize)
            let italicDescriptor = body.fontDescriptor.withSymbolicTraits(.traitItalic) ?? body.fontDescriptor
            let italic = UIFont(descriptor: italicDescriptor, size: body.pointSize)
            let mono = UIFont.monospacedSystemFont(ofSize: max(11, body.pointSize - 1), weight: .regular)
            let headings: [Int: UIFont] = [
                1: UIFont.preferredFont(forTextStyle: .title2),
                2: UIFont.preferredFont(forTextStyle: .title3),
                3: UIFont.systemFont(ofSize: body.pointSize + 2, weight: .semibold),
                4: UIFont.systemFont(ofSize: body.pointSize + 1, weight: .semibold),
                5: UIFont.systemFont(ofSize: body.pointSize, weight: .semibold),
                6: UIFont.systemFont(ofSize: body.pointSize, weight: .medium)
            ]
            return Theme(
                bodyFont: body,
                boldFont: bold,
                italicFont: italic,
                monospacedFont: mono,
                headingFonts: headings,
                linkColor: .link,
                listBullet: "•",
                listIndent: 20,
                listMarkerSpacing: 6,
                lineSpacing: 4,
                paragraphSpacing: 10,
                blockquoteIndicator: "▎",
                blockquoteIndicatorColor: UIColor.separator,
                blockquoteTextColor: UIColor.label.withAlphaComponent(0.85),
                blockquoteIndent: 12,
                codeBackgroundColor: UIColor.secondarySystemFill,
                codeTextColor: UIColor.label,
                codeCornerRadius: 4,
                codeParagraphSpacing: 8,
                horizontalRuleString: "────────────"
            )
            #endif
        }
    }

    private let plainCache = NSCache<NSString, NSString>()
    private let attributedCache = NSCache<NSString, NSAttributedString>()
    private let lock = NSLock()
    private let maxProcessLength = 50_000

    private init() {
        plainCache.countLimit = 400
        attributedCache.countLimit = 200
    }

    /// Returns a cached plain-text representation suitable for previews and search indices.
    func plainText(from markup: String) -> String {
        if markup.isEmpty { return markup }

        let key = markup
        lock.lock()
        if let cached = plainCache.object(forKey: key as NSString) {
            lock.unlock()
            return cached as String
        }
        lock.unlock()

        let normalized = normalizeLength(markup)
        let containsHTML = normalized.range(of: "<[^>]+>", options: .regularExpression) != nil

        let result: String
        if containsHTML {
            if Thread.isMainThread {
                let simplified = simplifiedStrip(normalized)
                DispatchQueue.global(qos: .utility).async { [weak self, cacheKey = key, normalizedCopy = normalized] in
                    guard let self else { return }
                    let processed = self.processHTML(normalizedCopy)
                    self.storePlain(processed, for: cacheKey)
                }
                result = simplified
            } else {
                result = processHTML(normalized)
            }
        } else {
            result = stripMarkupSyntax(normalized)
        }

        storePlain(result, for: key)
        return result
    }

    /// Renders markup (Markdown or HTML) into an attributed string using the supplied theme.
    func render(markup: String, theme: Theme = .podramsDefault) -> AttributedString {
        if markup.isEmpty { return AttributedString("") }
        let key = markup

        lock.lock()
        if let cached = attributedCache.object(forKey: key as NSString) {
            lock.unlock()
            return AttributedString(cached)
        }
        lock.unlock()

        let normalized = normalizeLineEndings(normalizeLength(markup))
        let isLikelyHTML = normalized.range(of: "<[^>]+>", options: .regularExpression) != nil

        let rendered: NSAttributedString
        if let markdown = parseMarkdown(normalized, theme: theme) {
            rendered = markdown
        } else if isLikelyHTML, let html = parseHTML(normalized, theme: theme) {
            rendered = html
        } else if let fallbackHTML = parseHTML(normalized, theme: theme) {
            rendered = fallbackHTML
        } else {
            rendered = NSAttributedString(string: normalized)
        }

        storeAttributed(rendered, for: key)
        return AttributedString(rendered)
    }

    // MARK: - Caching helpers

    private func storePlain(_ value: String, for key: String) {
        lock.lock()
        plainCache.setObject(value as NSString, forKey: key as NSString)
        lock.unlock()
    }

    private func storeAttributed(_ value: NSAttributedString, for key: String) {
        lock.lock()
        attributedCache.setObject(value, forKey: key as NSString)
        lock.unlock()
    }

    // MARK: - Markdown parsing

    private func parseMarkdown(_ markup: String, theme: Theme) -> NSAttributedString? {
        guard let attributed = try? AttributedString(markdown: markup, options: .init(interpretedSyntax: .full)) else {
            return nil
        }
        return buildAttributedString(from: attributed, theme: theme)
    }

    private func buildAttributedString(from markdown: AttributedString, theme: Theme) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var visitedParagraphs = Set<Int>()
        var paragraphStyles: [Int: NSMutableParagraphStyle] = [:]
        var lastComponents: [PresentationIntent.IntentType] = []
        var fallbackIdentity = 10_000

        var index = markdown.runs.startIndex
        while index != markdown.runs.endIndex {
            let run = markdown.runs[index]
            defer { index = markdown.runs.index(after: index) }

            let plain = markdown[run.range]
            let segmentText = String(plain.characters)
            if segmentText.isEmpty { continue }

            let components = run.presentationIntent?.components ?? []
            let identity = paragraphIdentity(for: components) ?? {
                fallbackIdentity += 1
                return fallbackIdentity
            }()

            let isNewParagraph = visitedParagraphs.insert(identity).inserted
            if isNewParagraph {
                if result.length > 0 {
                    let spacing = paragraphSpacing(between: lastComponents, and: components, theme: theme)
                    result.append(NSAttributedString(string: spacing))
                }
            }

            let paragraphStyle = paragraphStyles[identity] ?? style(for: components, theme: theme)
            paragraphStyles[identity] = paragraphStyle

            if isNewParagraph, let prefix = prefix(for: components, theme: theme, paragraphStyle: paragraphStyle) {
                result.append(prefix)
            }

            let body = styledSubstring(text: segmentText, theme: theme, run: run, components: components, paragraphStyle: paragraphStyle)
            result.append(body)

            lastComponents = components
        }

        applyParagraphWrapping(to: result)
        return result
    }

    private func paragraphIdentity(for components: [PresentationIntent.IntentType]) -> Int? {
        if let paragraph = components.first(where: { if case .paragraph = $0.kind { return true } else { return false } }) {
            return paragraph.identity
        }
        return components.last?.identity
    }

    private func paragraphSpacing(between previous: [PresentationIntent.IntentType], and current: [PresentationIntent.IntentType], theme: Theme) -> String {
        if previous.isEmpty { return "" }
        let previousLists = listComponents(in: previous)
        let currentLists = listComponents(in: current)
        if !previousLists.isEmpty && !currentLists.isEmpty {
            return "\n"
        }
        return "\n\n"
    }

    private func listComponents(in components: [PresentationIntent.IntentType]) -> [PresentationIntent.IntentType] {
        components.filter { component in
            switch component.kind {
            case .orderedList, .unorderedList, .listItem:
                return true
            default:
                return false
            }
        }
    }

    private func prefix(for components: [PresentationIntent.IntentType], theme: Theme, paragraphStyle: NSMutableParagraphStyle) -> NSAttributedString? {
        let listItems = components.filter { if case .listItem = $0.kind { return true } else { return false } }
        if let listItem = listItems.first {
            let level = listItems.count
            let listKinds = components.filter { component in
                if case .orderedList = component.kind { return true }
                if case .unorderedList = component.kind { return true }
                return false
            }
            let isOrdered = listKinds.first.map { component -> Bool in
                if case .orderedList = component.kind { return true }
                return false
            } ?? false

            let bulletPrefix: String
            if isOrdered {
                if case let .listItem(ordinal) = listItem.kind {
                    bulletPrefix = String(repeating: "  ", count: max(0, level - 1)) + "\(ordinal). "
                } else {
                    bulletPrefix = String(repeating: "  ", count: max(0, level - 1)) + "• "
                }
            } else {
                bulletPrefix = String(repeating: "  ", count: max(0, level - 1)) + "\(theme.listBullet) "
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: theme.bodyFont,
                .paragraphStyle: paragraphStyle
            ]
            return NSAttributedString(string: bulletPrefix, attributes: attributes)
        }

        if components.contains(where: { if case .blockQuote = $0.kind { return true } else { return false } }) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: theme.bodyFont,
                .foregroundColor: theme.blockquoteIndicatorColor,
                .paragraphStyle: paragraphStyle
            ]
            return NSAttributedString(string: "\(theme.blockquoteIndicator) ", attributes: attributes)
        }

        return nil
    }

    private func style(for components: [PresentationIntent.IntentType], theme: Theme) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = theme.lineSpacing
        style.paragraphSpacing = theme.paragraphSpacing

        let listDepth = components.reduce(into: 0) { partialResult, component in
            if case .listItem = component.kind { partialResult += 1 }
        }

        if listDepth > 0 {
            let indent = CGFloat(max(0, listDepth - 1)) * theme.listIndent
            style.firstLineHeadIndent = indent
            style.headIndent = indent + theme.listIndent - theme.listMarkerSpacing
        }

        if components.contains(where: { if case .blockQuote = $0.kind { return true } else { return false } }) {
            style.firstLineHeadIndent += theme.blockquoteIndent
            style.headIndent = style.firstLineHeadIndent
            style.paragraphSpacing = max(style.paragraphSpacing, theme.paragraphSpacing)
        }

        if components.contains(where: { if case .codeBlock = $0.kind { return true } else { return false } }) {
            style.paragraphSpacing = theme.codeParagraphSpacing
            style.firstLineHeadIndent = theme.blockquoteIndent
            style.headIndent = style.firstLineHeadIndent
        }

        return style
    }

    private func styledSubstring(text: String,
                                 theme: Theme,
                                 run: AttributedString.Runs.Run,
                                 components: [PresentationIntent.IntentType],
                                 paragraphStyle: NSMutableParagraphStyle) -> NSMutableAttributedString {
        let mutable = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        mutable.addAttribute(.font, value: theme.bodyFont, range: fullRange)

        if let inline = run.inlinePresentationIntent {
            if inline.contains(.code) {
                mutable.addAttribute(.font, value: theme.monospacedFont, range: fullRange)
                mutable.addAttribute(.backgroundColor, value: theme.codeBackgroundColor, range: fullRange)
                mutable.addAttribute(.foregroundColor, value: theme.codeTextColor, range: fullRange)
            } else {
                if inline.contains(.stronglyEmphasized) {
                    mutable.addAttribute(.font, value: theme.boldFont, range: fullRange)
                } else if inline.contains(.emphasized) {
                    mutable.addAttribute(.font, value: theme.italicFont, range: fullRange)
                }
                if inline.contains(.strikethrough) {
                    mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
                }
            }
        }

        if run.link != nil {
            mutable.addAttribute(.foregroundColor, value: theme.linkColor, range: fullRange)
            mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
            if let url = run.link {
                mutable.addAttribute(.link, value: url, range: fullRange)
            }
        }

        if let headerLevel = headerLevel(for: components), let headerFont = theme.headingFonts[headerLevel] {
            mutable.addAttribute(.font, value: headerFont, range: fullRange)
        }

        if components.contains(where: { if case .codeBlock = $0.kind { return true } else { return false } }) {
            mutable.addAttribute(.font, value: theme.monospacedFont, range: fullRange)
            mutable.addAttribute(.backgroundColor, value: theme.codeBackgroundColor, range: fullRange)
            mutable.addAttribute(.foregroundColor, value: theme.codeTextColor, range: fullRange)
        }

        if components.contains(where: { if case .blockQuote = $0.kind { return true } else { return false } }) {
            mutable.addAttribute(.foregroundColor, value: theme.blockquoteTextColor, range: fullRange)
        }

        return mutable
    }

    private func headerLevel(for components: [PresentationIntent.IntentType]) -> Int? {
        for component in components {
            if case let .header(level) = component.kind {
                return level
            }
        }
        return nil
    }

    // MARK: - HTML parsing

    private func parseHTML(_ markup: String, theme: Theme) -> NSAttributedString? {
        guard let rendered = normalizedAttributedString(fromHTML: markup) else {
            return nil
        }

        let mutable = NSMutableAttributedString(attributedString: rendered)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            guard let font = value as? PlatformFont else { return }
            let adjusted = adjustFont(font, bodyFont: theme.bodyFont)
            mutable.addAttribute(.font, value: adjusted, range: range)
        }
        mutable.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            guard let style = value as? NSMutableParagraphStyle else { return }
            style.lineSpacing = theme.lineSpacing
            style.paragraphSpacing = theme.paragraphSpacing
            mutable.addAttribute(.paragraphStyle, value: style, range: range)
        }
        mutable.enumerateAttribute(.link, in: fullRange, options: []) { value, range, _ in
            guard value != nil else { return }
            mutable.addAttribute(.foregroundColor, value: theme.linkColor, range: range)
            mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }

        return mutable
    }

    private func adjustFont(_ incoming: PlatformFont, bodyFont: PlatformFont) -> PlatformFont {
        #if os(macOS)
        if incoming.fontDescriptor.symbolicTraits.contains(.bold) {
            return NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
        }
        if incoming.fontDescriptor.symbolicTraits.contains(.italic) {
            return NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
        }
        if let adjusted = PlatformFont(descriptor: incoming.fontDescriptor, size: bodyFont.pointSize) {
            return adjusted
        }
        return bodyFont
        #else
        if incoming.fontDescriptor.symbolicTraits.contains(.traitBold) {
            if let descriptor = bodyFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: descriptor, size: bodyFont.pointSize)
            }
        }
        if incoming.fontDescriptor.symbolicTraits.contains(.traitItalic) {
            if let descriptor = bodyFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
                return UIFont(descriptor: descriptor, size: bodyFont.pointSize)
            }
        }
        return UIFont(descriptor: incoming.fontDescriptor, size: bodyFont.pointSize)
        #endif
    }

    private func normalizedAttributedString(fromHTML html: String) -> NSAttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }
        if data.count > maxProcessLength {
            // Avoid parsing extremely large blobs on the main thread; fall back to simplified strip.
            return NSAttributedString(string: simplifiedStrip(html))
        }

        return autoreleasepool {
            do {
                let rendered = try NSMutableAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ],
                    documentAttributes: nil
                )

                let range = NSRange(location: 0, length: rendered.length)
                rendered.enumerateAttribute(.font, in: range, options: []) { _, subRange, _ in
                    rendered.removeAttribute(.font, range: subRange)
                }
                rendered.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subRange, _ in
                    guard let style = value as? NSMutableParagraphStyle else { return }
                    style.lineBreakMode = .byWordWrapping
                    rendered.addAttribute(.paragraphStyle, value: style, range: subRange)
                }
                return rendered
            } catch {
                return nil
            }
        }
    }

    // MARK: - Plain text helpers

    private func simplifiedStrip(_ html: String) -> String {
        var result = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func processHTML(_ html: String) -> String {
        guard let attributed = normalizedAttributedString(fromHTML: html) else {
            return simplifiedStrip(html)
        }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripMarkupSyntax(_ input: String) -> String {
        var working = input
        let replacements: [(pattern: String, template: String)] = [
            ("\\*\\*(.+?)\\*\\*", "$1"),
            ("\\*(.+?)\\*", "$1"),
            ("__(.+?)__", "$1"),
            ("~~(.+?)~~", "$1"),
            ("`([^`]+)`", "$1"),
            ("\\[(.+?)\\]\\(([^)]+)\\)", "$1")
        ]
        for replacement in replacements {
            if let regex = try? NSRegularExpression(pattern: replacement.pattern, options: []) {
                working = regex.stringByReplacingMatches(in: working, options: [], range: NSRange(location: 0, length: working.utf16.count), withTemplate: replacement.template)
            }
        }
        return working.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeLength(_ input: String) -> String {
        if input.count > maxProcessLength {
            let truncated = input.prefix(maxProcessLength)
            return String(truncated) + "... [truncated]"
        }
        return input
    }

    private func normalizeLineEndings(_ input: String) -> String {
        input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private func applyParagraphWrapping(to attributed: NSMutableAttributedString, maxLength: Int = 420) {
        guard attributed.length > maxLength else { return }

        let original = attributed.string as NSString
        var insertionPoints: [Int] = []
        let whitespace = CharacterSet.whitespacesAndNewlines

        var paragraphStart = 0
        while paragraphStart < original.length {
            let paragraphRange = original.paragraphRange(for: NSRange(location: paragraphStart, length: 0))
            let paragraphEnd = NSMaxRange(paragraphRange)
            if paragraphRange.length > maxLength {
                var current = paragraphRange.location
                while current + maxLength < paragraphEnd {
                    let remaining = paragraphEnd - current
                    let searchLength = min(maxLength, remaining)
                    let searchRange = NSRange(location: current, length: searchLength)
                    let breakRange = original.rangeOfCharacter(from: whitespace, options: [.backwards], range: searchRange)
                    var breakIndex: Int
                    if breakRange.location != NSNotFound, breakRange.location > current {
                        breakIndex = breakRange.location + breakRange.length
                    } else {
                        breakIndex = current + searchLength
                    }
                    breakIndex = min(breakIndex, paragraphEnd)
                    if breakIndex <= current { breakIndex = current + searchLength }
                    insertionPoints.append(breakIndex)
                    current = breakIndex
                }
            }
            paragraphStart = paragraphEnd
        }

        guard !insertionPoints.isEmpty else { return }

        for insertionPoint in insertionPoints.sorted(by: >) {
            let index = min(insertionPoint, attributed.length)
            let attributes: [NSAttributedString.Key: Any]
            if index > 0 {
                attributes = attributed.attributes(at: index - 1, effectiveRange: nil)
            } else {
                attributes = [:]
            }
            let lineBreak = NSAttributedString(string: "\n", attributes: attributes)
            attributed.insert(lineBreak, at: index)
        }
    }
}

extension ZMarkupParser: @unchecked Sendable {}
