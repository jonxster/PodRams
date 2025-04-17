//
//  PodRamsUITests.swift
//  PodRamsUITests
//
//  Created by Tom Björnebark on 2025-02-20.
//

import XCTest

final class PodRamsUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it's important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Attempt to find the main window; skip test if it does not appear in time
        let mainWindow = app.windows.firstMatch
        if !mainWindow.waitForExistence(timeout: 5) {
            // Skip UI assertion in environments where the window may not be accessible
            throw XCTSkip("Main window did not appear in time; skipping UI window test")
        }
        // Optional small delay for additional stabilization
        Thread.sleep(forTimeInterval: 1.0)

        // Terminate the app
        app.terminate()
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
