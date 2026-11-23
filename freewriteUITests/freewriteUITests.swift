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
    func testDestinationSettingsOnlyPersistOnSave() throws {
        let app = XCUIApplication()
        let name = app.textFields["Display name"]
        let save = app.buttons["Save"]

        app.launch()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.buttons["Reveal in Finder"].isEnabled)
        let originalName = try XCTUnwrap(name.value as? String)
        let editedName = "Journal \(UUID().uuidString.prefix(8))"

        func enterName(_ newName: String) {
            name.click()
            name.typeKey("a", modifierFlags: .command)
            name.typeText(newName)
        }

        enterName(editedName)
        XCTAssertTrue(save.isEnabled)

        app.terminate()
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertEqual(name.value as? String, originalName)

        enterName(editedName)
        save.click()
        XCTAssertFalse(save.isEnabled)

        app.terminate()
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertEqual(name.value as? String, editedName)

        enterName(originalName)
        save.click()
        XCTAssertFalse(save.isEnabled)
    }

    @MainActor
    func testHiddenInvalidRollingFormatDoesNotEnableSaveOrPersist() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey(",", modifierFlags: .command)

        let save = app.buttons["Save"]
        let rolling = app.buttons["Rolling"]
        let newNote = app.buttons["New note"]
        let format = app.textFields["yyyy-MM-dd"]
        let name = app.textFields["Display name"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        let originalName = try XCTUnwrap(name.value as? String)

        rolling.click()
        XCTAssertTrue(format.waitForExistence(timeout: 5))
        let savedFormat = try XCTUnwrap(format.value as? String)
        format.click()
        format.typeKey("a", modifierFlags: .command)
        format.typeText("yyyy/MM/dd")
        let warning = app.staticTexts["Invalid format (no path separators; basename only)"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)

        newNote.click()
        XCTAssertFalse(format.exists)
        XCTAssertFalse(save.isEnabled)

        name.click()
        name.typeText(" edited")
        XCTAssertTrue(save.isEnabled)
        save.click()
        XCTAssertFalse(save.isEnabled)
        app.buttons["Cancel"].click()

        app.typeKey(",", modifierFlags: .command)
        XCTAssertEqual(name.value as? String, originalName + " edited")
        rolling.click()
        XCTAssertEqual(format.value as? String, savedFormat)
        XCTAssertFalse(warning.exists)

        newNote.click()
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText(originalName)
        save.click()
        XCTAssertFalse(save.isEnabled)
    }

    @MainActor
    func testHiddenInvalidRollingFormatUsesNewPeriodDefault() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey(",", modifierFlags: .command)

        let rolling = app.buttons["Rolling"]
        let newNote = app.buttons["New note"]
        let save = app.buttons["Save"]
        let format = app.textFields["yyyy-MM-dd"]
        let daily = app.buttons["Daily"]
        let monthly = app.buttons["Monthly"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))

        func enterFormat(_ value: String) {
            format.click()
            format.typeKey("a", modifierFlags: .command)
            format.typeText(value)
        }

        rolling.click()
        let originalFormat = try XCTUnwrap(format.value as? String)
        monthly.click()
        let expectedMonthlyFormat = format.value as? String
        enterFormat("yyyy/MM/dd")
        XCTAssertFalse(save.isEnabled)
        newNote.click()
        XCTAssertTrue(save.isEnabled)
        save.click()

        app.terminate()
        app.launch()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        rolling.click()
        XCTAssertTrue(format.waitForExistence(timeout: 5))
        let savedMonthlyFormat = format.value as? String

        daily.click()
        if (format.value as? String) != originalFormat {
            enterFormat(originalFormat)
        }
        newNote.click()
        save.click()

        XCTAssertEqual(expectedMonthlyFormat, "yyyy-MM")
        XCTAssertEqual(savedMonthlyFormat, expectedMonthlyFormat)
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
        let header = app.buttons["historyHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(header.label.contains("Quick Note"))
        XCTAssertFalse(header.label.contains("/"), "History should show the destination name, not its path")

        let row = app.staticTexts[seed]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(hasKeyboardFocus(app.textViews.firstMatch), "Editor lost focus after selecting a History note")

        app.typeText("ZZ")

        let value = app.textViews.firstMatch.value as? String ?? ""
        XCTAssertTrue(value.contains("ZZ"), "Typed text was dropped; editor holds: \(value)")
    }

    @MainActor
    func testHistorySearchMatchesTitleAndBody() throws {
        let app = XCUIApplication()
        app.launch()

        let tag = UUID().uuidString.prefix(8).lowercased()
        let firstTitle = "search alpha \(tag)"
        let secondTitle = "search beta \(tag)"
        let editor = app.textViews["mainEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("\(firstTitle)\nbody mentions zucchini\(tag)")
        app.buttons["New Note"].click()
        editor.click()
        editor.typeText("\(secondTitle)\nbody mentions okra")
        app.buttons["New Note"].click()

        app.buttons["historyButton"].click()
        let search = app.textFields["historySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[firstTitle].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[secondTitle].exists)

        search.click()
        search.typeText("ZUCCHINI\(tag)")
        XCTAssertTrue(app.staticTexts[firstTitle].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[secondTitle].exists, "Body search kept a non-matching note")

        search.typeKey("a", modifierFlags: .command)
        search.typeText("beta \(tag)")
        XCTAssertTrue(app.staticTexts[secondTitle].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[firstTitle].exists, "Title search kept a non-matching note")

        search.typeKey("a", modifierFlags: .command)
        search.typeText("nomatch\(tag)")
        XCTAssertTrue(app.staticTexts["historySearchEmpty"].waitForExistence(timeout: 5))

        app.buttons["historySearchClear"].click()
        XCTAssertTrue(app.staticTexts[firstTitle].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[secondTitle].exists)

        search.click()
        search.typeText("zucchini\(tag)")
        let match = app.staticTexts[firstTitle]
        XCTAssertTrue(match.waitForExistence(timeout: 5))
        match.click()
        XCTAssertTrue(hasKeyboardFocus(editor), "Editor lost focus after selecting a filtered History note")
        app.typeText("QQ")
        XCTAssertEqual(search.value as? String, "zucchini\(tag)", "Typing after selection went into History search")
        XCTAssertTrue((editor.value as? String ?? "").contains("QQ"), "Typed text did not reach the editor")
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
    func testVisibleInvalidRollingEditPromptsBeforeOpeningHistory() throws {
        let app = XCUIApplication()
        app.launch()
        app.typeKey(",", modifierFlags: .command)

        let save = app.buttons["Save"]
        let format = app.textFields["yyyy-MM-dd"]
        let keepEditing = app.windows.firstMatch.sheets.firstMatch.buttons["Keep Editing"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        app.buttons["Rolling"].click()
        save.click()

        format.click()
        format.typeKey("a", modifierFlags: .command)
        format.typeText("yyyy/MM/dd")
        XCTAssertFalse(save.isEnabled)
        app.buttons["historyButton"].click()

        let prompted = keepEditing.waitForExistence(timeout: 3)
        if prompted {
            keepEditing.click()
        } else {
            app.typeKey(",", modifierFlags: .command)
        }
        let draftFormat = format.value as? String
        let couldSave = save.isEnabled

        app.buttons["New note"].click()
        save.click()

        XCTAssertTrue(prompted, "Opening History should ask before dropping a visible invalid edit")
        XCTAssertEqual(draftFormat, "yyyy/MM/dd")
        XCTAssertFalse(couldSave)
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
