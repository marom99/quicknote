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
    func testEditorKeepsFocusAfterThemeToggleThenHistorySelection() throws {
        let app = XCUIApplication()
        app.launch()

        let seed = "theme focus seed \(UUID().uuidString.prefix(8).lowercased())"
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText(seed)
        app.buttons["New Note"].click()

        app.buttons["themeToggleButton"].click()
        XCTAssertTrue(hasKeyboardFocus(app.textViews.firstMatch), "Editor lost focus after theme toggle")

        app.buttons["historyButton"].click()
        let row = app.staticTexts[seed]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(hasKeyboardFocus(app.textViews.firstMatch), "Editor lost focus after selecting a History note")

        app.typeText("ZZ")

        let value = app.textViews.firstMatch.value as? String ?? ""
        XCTAssertTrue(value.contains("ZZ"), "Typed text was dropped; editor holds: \(value)")
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        element.value(forKey: "hasKeyboardFocus") as? Bool ?? false
    }

    @MainActor
    func testNewEntryStaysSingleLineWithCompactDestinationSettings() throws {
        let app = XCUIApplication()
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let frame = window.frame
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -1, dy: -1))
        corner.press(forDuration: 0.1, thenDragTo: corner.withOffset(
            CGVector(dx: 480 - frame.width, dy: 540 - frame.height)
        ))
        XCTAssertEqual(window.frame.width, 480, accuracy: 1)

        let newEntry = app.buttons["New Note"]
        let originalHeight = newEntry.frame.height
        XCTAssertGreaterThan(originalHeight, 0)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Destination settings"].waitForExistence(timeout: 5))
        let singleLine = NSPredicate { _, _ in
            abs(newEntry.frame.height - originalHeight) < 1
        }
        expectation(for: singleLine, evaluatedWith: newEntry)
        waitForExpectations(timeout: 5)
        XCTAssertLessThanOrEqual(newEntry.frame.height, 20)
        XCTAssertTrue(window.frame.contains(newEntry.frame))
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
