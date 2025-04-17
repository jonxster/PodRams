import XCTest

@MainActor
final class AudioOutputSelectionUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testAudioOutputSelectionView_structure() throws {
        // Tap the audio output toolbar button
        let audioButton = app.buttons["AudioOutputButton"]
        XCTAssertTrue(audioButton.waitForExistence(timeout: 5), "Audio output toolbar button not found")
        audioButton.tap()

        // Verify the selection view appears
        let selectionView = app.otherElements["AudioOutputSelectionView"]
        XCTAssertTrue(selectionView.waitForExistence(timeout: 5), "Audio Output Selection view did not appear")

        // Check that the selected device row exists with a checkmark
        let selectedRow = selectionView.buttons["AudioOutput_SelectedDeviceRow"]
        XCTAssertTrue(selectedRow.exists, "Selected device row not found")
        let checkmark = selectedRow.images["checkmark"]
        XCTAssertTrue(checkmark.exists, "Checkmark not found in selected device row")

        // Find other device rows
        let otherRows = selectionView.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "AudioOutput_DeviceRow_"))
        let header = selectionView.staticTexts["AudioOutput_SwitchToHeader"]
        if otherRows.count > 0 {
            XCTAssertTrue(header.exists, "Switch to header should appear when other devices exist")
            // Tap the first other device; should dismiss the popover
            let firstOther = otherRows.element(boundBy: 0)
            XCTAssertTrue(firstOther.exists, "No other device row found despite count > 0")
            firstOther.tap()
            XCTAssertFalse(selectionView.exists, "Selection view should close after selecting another device")
        } else {
            XCTAssertFalse(header.exists, "Switch to header should not appear when there is only one device")
            // Tap the selected row; should dismiss the popover
            selectedRow.tap()
            XCTAssertFalse(selectionView.exists, "Selection view should close after selecting the device")
        }
    }
}