import XCTest
#if SWIFT_PACKAGE
@testable import PodRamsCore
#else
@testable import PodRams
#endif

#if os(macOS)
import AppKit
private typealias TestFont = NSFont
#else
import UIKit
private typealias TestFont = UIFont
#endif

final class ZMarkupParserTests: XCTestCase {

    func testMarkdownListProducesBullets() {
        let markup = "- First item\n- Second item"
        let rendered = ZMarkupParser.shared.render(markup: markup)
        let text = String(rendered.characters)
        XCTAssertTrue(text.contains("• First item"), "Expected bullet prefix for first item")
        XCTAssertTrue(text.contains("\n• Second item"), "Expected bullet prefix for subsequent items")
    }

    func testBoldItalicAndCodeAttributesApplyFonts() {
        let markup = "Make **bold**, *italic*, and `code`."
        let rendered = ZMarkupParser.shared.render(markup: markup)
        let foundation = NSAttributedString(rendered)

        var foundBold = false
        var foundItalic = false
        var foundCode = false

        foundation.enumerateAttributes(in: NSRange(location: 0, length: foundation.length), options: []) { attributes, range, _ in
            guard range.length > 0 else { return }
            let substring = (foundation.string as NSString).substring(with: range)
            guard let font = attributes[.font] as? TestFont else { return }

            let traits = font.fontDescriptor.symbolicTraits

            if substring.contains("bold") {
                #if os(macOS)
                foundBold = traits.contains(.bold)
                #else
                foundBold = traits.contains(.traitBold)
                #endif
            } else if substring.contains("italic") {
                #if os(macOS)
                foundItalic = traits.contains(.italic)
                #else
                foundItalic = traits.contains(.traitItalic)
                #endif
            } else if substring.contains("code") {
                #if os(macOS)
                foundCode = traits.contains(.monoSpace)
                #else
                foundCode = traits.contains(.traitMonoSpace)
                #endif
            }
        }

        XCTAssertTrue(foundBold, "Bold text should use a bold font variant")
        XCTAssertTrue(foundItalic, "Italic text should use an italic font variant")
        XCTAssertTrue(foundCode, "Inline code should use a monospaced font")
    }

    func testBlockQuoteAddsIndicator() {
        let markup = "> Insightful remark"
        let rendered = ZMarkupParser.shared.render(markup: markup)
        let text = String(rendered.characters)
        XCTAssertTrue(text.hasPrefix("▎"), "Block quotes should begin with an indicator symbol")
    }

    func testLongParagraphGetsWrappedWithNewlines() {
        let paragraph = Array(repeating: "Lorem ipsum dolor sit amet", count: 100).joined(separator: " ")
        let rendered = ZMarkupParser.shared.render(markup: paragraph)
        let text = String(rendered.characters)
        XCTAssertTrue(text.contains("\n"), "Long paragraphs should receive injected line breaks")
    }

    func testLinksPreserveURLAttribute() {
        let url = URL(string: "https://example.com/path")!
        let markup = "Please [click here](\(url.absoluteString)) for details."
        let rendered = ZMarkupParser.shared.render(markup: markup)

        var foundLink = false
        var index = rendered.runs.startIndex
        while index != rendered.runs.endIndex {
            let run = rendered.runs[index]
            if run.link == url {
                foundLink = true
                break
            }
            index = rendered.runs.index(after: index)
        }

        XCTAssertTrue(foundLink, "Rendered output should retain tappable URL metadata")
    }
}
