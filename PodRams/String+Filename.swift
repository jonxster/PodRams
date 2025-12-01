import Foundation

extension String {
    func sanitizedForFilename() -> String {
        if #available(macOS 26.0, iOS 26.0, *) {
            return _sanitizeFilenameSpan(self)
        } else {
            // Fallback: strip disallowed characters with simple String operations.
            let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
            let components = self.components(separatedBy: invalid)
            let condensed = components.joined(separator: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(condensed.prefix(80))
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    private func _sanitizeFilenameSpan(_ value: String) -> String {
        // Use UTF8Span + UnicodeScalarIterator to filter invalid characters without extra copies.
        var utf8Span = value.utf8Span
        _ = utf8Span.checkForASCII() // Hint fast path for all-ASCII names.

        let invalid: Set<UnicodeScalar> = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
        var buffer: [UInt8] = []
        buffer.reserveCapacity(utf8Span.count)

        var previousWasSpace = false
        var scalarIterator = utf8Span.makeUnicodeScalarIterator()
        while let scalar = scalarIterator.next() {
            if invalid.contains(scalar) { continue }
            if scalar.value < 0x20 || scalar.value == 0x7F { continue } // control chars

            if scalar.properties.isWhitespace {
                if previousWasSpace { continue }
                previousWasSpace = true
                buffer.append(32) // space
                continue
            }

            previousWasSpace = false
            buffer.append(contentsOf: scalar.utf8)
        }

        while buffer.last == 32 { buffer.removeLast() }
        return String(decoding: buffer.prefix(80), as: UTF8.self)
    }
}
