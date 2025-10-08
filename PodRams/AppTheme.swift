import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum AppTheme {
    enum Mode: String, CaseIterable { case light, dark }

    enum ColorToken: String {
        case background
        case surface
        case hoverSurface
        case toolbarBackground
        case accent
        case primaryText
        case secondaryText
    }

    static var background: Color { color(.background) }
    static var surface: Color { color(.surface) }
    static var hoverSurface: Color { color(.hoverSurface) }
    static var toolbarBackground: Color { color(.toolbarBackground) }
    static var accent: Color { color(.accent) }
    static var primaryText: Color { color(.primaryText) }
    static var secondaryText: Color { color(.secondaryText) }

    static func color(_ token: ColorToken, in mode: Mode? = nil) -> Color {
        let resolved = mode ?? resolvedMode()
        return ColorSchemeLoader.shared.color(for: token, mode: resolved)
    }

    private static func resolvedMode() -> Mode {
        #if os(macOS)
        if let appearance = NSApp?.effectiveAppearance,
           let match = appearance.bestMatch(from: [.darkAqua, .aqua]) {
            return match == .darkAqua ? .dark : .light
        }
        #elseif canImport(UIKit)
        // Prefer the first active window scene to determine the current interface style
        if let style = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.traitCollection.userInterfaceStyle })
            .first(where: { $0 != .unspecified }) {
            return style == .dark ? .dark : .light
        }
        #endif
        return .light
    }
}

@MainActor
final class ColorSchemeLoader {
    static let shared = ColorSchemeLoader()

    private(set) var colors: [AppTheme.Mode: [AppTheme.ColorToken: Color]] = ColorSchemeLoader.defaultPalette

    private init() {
        load()
    }

    func color(for token: AppTheme.ColorToken, mode: AppTheme.Mode) -> Color {
        colors[mode]?[token] ?? ColorSchemeLoader.defaultPalette[mode]?[token] ?? ColorSchemeLoader.defaultPalette[.dark]?[token] ?? .white
    }

    private func load() {
        colors = ColorSchemeLoader.defaultPalette

        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "ColorScheme", withExtension: "xml"),
              let data = try? Data(contentsOf: url),
              let document = try? XMLDocument(data: data, options: .nodePreserveAll),
              let root = document.rootElement() else {
            return
        }

        for modeElement in root.elements(forName: "Mode") {
            guard let name = modeElement.attribute(forName: "name")?.stringValue?.lowercased(),
                  let mode = AppTheme.Mode(rawValue: name) else { continue }

            var bucket = colors[mode] ?? [:]
            for colorElement in modeElement.elements(forName: "Color") {
                guard let tokenName = colorElement.attribute(forName: "name")?.stringValue,
                      let token = AppTheme.ColorToken(rawValue: tokenName),
                      let value = colorElement.attribute(forName: "value")?.stringValue,
                      let resolved = Color(hexString: value) else { continue }
                bucket[token] = resolved
            }
            colors[mode] = bucket
        }
    }

    private static var defaultPalette: [AppTheme.Mode: [AppTheme.ColorToken: Color]] {
        let dark: [AppTheme.ColorToken: Color] = [
            .background: Color(hex: 0x0F0F0F),
            .surface: Color(hex: 0x171C21),
            .hoverSurface: Color(hex: 0x1F262C),
            .toolbarBackground: Color(hex: 0x0F0F0F),
            .accent: Color(hex: 0x55D1FF),
            .primaryText: .white,
            .secondaryText: Color.white.opacity(0.7)
        ]

        let light: [AppTheme.ColorToken: Color] = [
            .background: Color(hex: 0xFFFFFF),
            .surface: Color(hex: 0xFFFFFF),
            .hoverSurface: Color(hex: 0xE2E8EE),
            .toolbarBackground: Color(hex: 0xFFFFFF),
            .accent: Color(hex: 0x007AFF),
            .primaryText: Color(hex: 0x1C1C1E),
            .secondaryText: Color.black.opacity(0.65)
        ]

        return [.dark: dark, .light: light]
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init?(hexString: String, alpha: Double = 1.0) {
        var sanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard let value = UInt32(sanitized, radix: 16) else { return nil }
        self.init(hex: value, alpha: alpha)
    }
}
