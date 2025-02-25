//
//  KeyboardShortcutView.swift
//  PodRams
//
//  Created by Tom Björnebark on 2025-02-25.
//

// KeyboardShortcutView..swift

import SwiftUI
import AppKit

struct KeyboardShortcutView: NSViewRepresentable {
    var onKeyPress: (KeyType) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 49 { // Space key
                onKeyPress(.space)
            } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
                onKeyPress(.commandF)
            } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
                onKeyPress(.commandC)
            }
            return event
        }
        
        context.coordinator.eventMonitor = eventMonitor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var eventMonitor: Any?
        deinit {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

enum KeyType {
    case space
    case commandF
    case commandC
}
