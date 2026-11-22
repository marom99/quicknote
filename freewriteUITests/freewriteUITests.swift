//
//  freewriteUITests.swift
//  freewriteUITests
//
//  Created by thorfinn on 2/14/25.
//

import XCTest

final class freewriteUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testTypingImmediatelyAfterLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        app.typeText("Launch focus regression")

        XCTAssertEqual(app.textViews["mainEditor"].value as? String, "Launch focus regression")
    }

    @MainActor
    func testTypingAfterCancelingDestinationSettings() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        let name = app.textFields["Display name"]
        name.click()
        name.typeText(" edited")
        app.buttons["Cancel"].click()

        app.typeText("Typing after Cancel")

        XCTAssertEqual(app.textViews["mainEditor"].value as? String, "Typing after Cancel")
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
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
