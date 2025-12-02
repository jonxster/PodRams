import SwiftUI
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum AppTheme {
    // Mode is kept for API compatibility but is no longer actively used for resolution
    // since system colors adapt automatically.
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

    // MARK: - Semantic Colors

    static var background: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    static var surface: Color {
        #if os(macOS)
        // Using controlBackgroundColor provides a standard "surface" look for lists/cards.
        // alternatively .textBackgroundColor for lighter surfaces.
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var hoverSurface: Color {
        #if os(macOS)
        // A system-standard gray for hover/unemphasized selection
        return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        #else
        return Color.secondary.opacity(0.15)
        #endif
    }

    static var toolbarBackground: Color {
        // Standard window background works well for toolbars to blend in
        return background
    }

    static var accent: Color {
        return Color.accentColor
    }

    static var primaryText: Color {
        return Color.primary
    }

    static var secondaryText: Color {
        return Color.secondary
    }

    // MARK: - API Compatibility

    /// Returns the color for the given token.
    /// - Parameters:
    ///   - token: The color token to resolve.
    ///   - mode: Ignored. System colors automatically adapt to the current `ColorScheme` in the view hierarchy.
    static func color(_ token: ColorToken, in mode: Mode? = nil) -> Color {
        switch token {
        case .background: return background
        case .surface: return surface
        case .hoverSurface: return hoverSurface
        case .toolbarBackground: return toolbarBackground
        case .accent: return accent
        case .primaryText: return primaryText
        case .secondaryText: return secondaryText
        }
    }
}