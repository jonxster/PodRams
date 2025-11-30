//
//  KeyboardShortcutView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

// KeyboardShortcutView..swift

import SwiftUI
import AppKit

@MainActor
struct KeyboardShortcutView: NSViewRepresentable {
    var onKeyPress: (KeyType) -> Void
    var shouldHandleKey: () -> Bool = { true }
    
    func makeNSView(context: Context) -> MonitorHostView {
        let view = MonitorHostView()
        view.installMonitorIfNeeded {
            guard shouldHandleKey() else { return $0 }
            if let key = KeyboardShortcutView.keyType(for: $0) {
                onKeyPress(key)
                // Consume handled shortcuts so they reliably trigger even when other controls are focused.
                return nil
            }
            return $0
        }
        return view
    }

    func updateNSView(_ nsView: MonitorHostView, context: Context) {
        nsView.installMonitorIfNeeded {
            guard shouldHandleKey() else { return $0 }
            if let key = KeyboardShortcutView.keyType(for: $0) {
                onKeyPress(key)
                return nil
            }
            return $0
        }
    }

    /// View that owns the NSEvent monitor so it can cleanly remove it when detached.
    @MainActor
    final class MonitorHostView: NSView {
        private var eventMonitor: Any?

        func installMonitorIfNeeded(handler: @escaping (NSEvent) -> NSEvent?) {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                tearDownMonitor()
            }
        }

        deinit {
            tearDownMonitor()
        }

        /// Schedules teardown on the main actor; safe to call from nonisolated contexts like deinit.
        nonisolated private func tearDownMonitor() {
            Task { @MainActor in
                guard let monitor = eventMonitor else { return }
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }

    /// Maps NSEvent instances to our app-specific key types.
    nonisolated static func keyType(for event: NSEvent) -> KeyType? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)
        let hasControl = flags.contains(.control)
        let keyCode = Int(event.keyCode)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let originalCharacters = event.characters ?? ""

        // Space (no modifiers)
        if keyCode == 49 && !hasCommand && !hasOption && !hasControl {
            return .space
        }

        // Command-only letter shortcuts and +/- volume keys
        if hasCommand && !hasOption && !hasControl {
            switch characters {
            case "f": return .commandF
            case "c": return .commandC
            case "p": return .commandP
            case "s": return .commandS
            case "m": return .commandM
            case "=","+": return .commandPlus
            case "-": return .commandMinus
            default: break
            }
        }

        // Plain plus/minus/m when not typing
        if !hasCommand && !hasOption && !hasControl {
            switch originalCharacters.lowercased() {
            case "m": return .plainM
            case "+": return .plainPlus
            case "-": return .plainMinus
            default: break
            }
        }

        // Arrow combinations
        switch keyCode {
        case 123: // left arrow
            if hasCommand && hasOption && !hasControl { return .optionCommandLeft }
            if hasCommand && !hasOption && !hasControl { return .commandLeft }
        case 124: // right arrow
            if hasCommand && hasOption && !hasControl { return .optionCommandRight }
            if hasCommand && !hasOption && !hasControl { return .commandRight }
        case 125: // down arrow
            if hasCommand && !hasOption && !hasControl { return .commandDown }
        case 126: // up arrow
            if hasCommand && !hasOption && !hasControl { return .commandUp }
        default:
            break
        }

        return nil
    }
}

enum KeyType {
    case space
    case commandF
    case commandC
    case commandP
    case commandS
    case commandLeft
    case commandRight
    case optionCommandLeft
    case optionCommandRight
    case commandUp
    case commandDown
    case commandM
    case commandPlus
    case commandMinus
    case plainPlus
    case plainMinus
    case plainM
}
