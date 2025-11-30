import XCTest
import AppKit
#if SWIFT_PACKAGE
@testable import PodRamsCore
#else
@testable import PodRams
#endif

final class KeyboardShortcutViewTests: XCTestCase {

    func testSpaceMapsToSpaceKey() {
        let event = keyEvent(keyCode: 49, modifiers: [])
        XCTAssertEqual(KeyboardShortcutView.keyType(for: event), .space)
    }

    func testCommandLetterShortcuts() {
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 35, characters: "p", modifiers: [.command])), .commandP)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 1, characters: "s", modifiers: [.command])), .commandS)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 8, characters: "c", modifiers: [.command])), .commandC)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 3, characters: "f", modifiers: [.command])), .commandF)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 46, characters: "m", modifiers: [.command])), .commandM)
    }

    func testPlainLetterAndSymbols() {
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 46, characters: "m", modifiers: [])), .plainM)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 24, characters: "+", modifiers: [.shift])), .plainPlus)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 27, characters: "-", modifiers: [])), .plainMinus)
    }

    func testArrowShortcuts() {
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 123, modifiers: [.command])), .commandLeft)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 124, modifiers: [.command])), .commandRight)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 123, modifiers: [.command, .option])), .optionCommandLeft)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 124, modifiers: [.command, .option])), .optionCommandRight)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 126, modifiers: [.command])), .commandUp)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 125, modifiers: [.command])), .commandDown)
    }

    func testUnmappedEventsReturnNil() {
        XCTAssertNil(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 49, modifiers: [.command]))) // command + space not mapped
        XCTAssertNil(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 15, characters: "r", modifiers: [.command]))) // unrelated command
        XCTAssertNil(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 35, characters: "p", modifiers: [.command, .option]))) // extra modifier
    }

    func testCommandPlusMinusVolume() {
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 24, characters: "=", modifiers: [.command])), .commandPlus)
        XCTAssertEqual(KeyboardShortcutView.keyType(for: keyEvent(keyCode: 27, characters: "-", modifiers: [.command])), .commandMinus)
    }

    // MARK: - Helpers
    private func keyEvent(
        keyCode: Int,
        characters: String? = nil,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        let chars = characters ?? (keyCode == 49 ? " " : "")
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }
}
