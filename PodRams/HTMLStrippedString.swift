import Foundation

extension String {
    /// Returns a cached plain-text representation suitable for summaries.
    var htmlStripped: String {
        ZMarkupParser.shared.plainText(from: self)
    }

    /// Renders the receiver into a themed attributed string for display.
    func htmlRenderedAttributedString(theme: ZMarkupParser.Theme = .podramsDefault) -> AttributedString {
        ZMarkupParser.shared.render(markup: self, theme: theme)
    }
}
