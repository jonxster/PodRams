//
//  HTMLStrippedString.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-21.
//

import Foundation
import AppKit

extension String {
    /// Konverterar en HTML-sträng till ren text (strippad från <p>, <br> etc.)
    /// Använder NSAttributedString för macOS (AppKit).
    var htmlStripped: String {
        guard let data = self.data(using: .utf8) else {
            return self
        }
        do {
            let attributed = try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
            return attributed.string
        } catch {
            // Om något går fel, fall back
            return self
        }
    }
}
