//
//  CoPaReUITests.swift
//  CoPaReUITests
//
//  Created by CoPaRe contributors.
//

import XCTest

final class CoPaReUITests: XCTestCase {

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
    func testIsolatedMainWindowLaunches() throws {
        let app = XCUIApplication()
        app.launchEnvironment["COPARE_UI_TESTS"] = "1"
        app.launch()
        XCTAssertTrue(app.windows["CoPaRe"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStatusMenuCanReopenTheMainWindow() throws {
        let app = launchIsolatedApplication()
        let statusItem = app.descendants(matching: .any)["CoPaReStatusItem"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        let menu = statusItem.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])

        app.activate()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows["CoPaRe"].waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.menuItems["Open CoPaRe"].click()
        XCTAssertTrue(app.windows["CoPaRe"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSnippetCanBeCreatedEditedAndRevealed() throws {
        let app = launchIsolatedApplication()
        createSnippet(in: app, title: "Original snippet", body: "Original body", tags: "original")

        let actions = app.descendants(matching: .any)["clipboardItemActions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.click()
        app.menuItems["Edit Snippet…"].click()

        let title = app.textFields["snippetTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Original snippet")
        let body = app.textViews["snippetBody"]
        XCTAssertEqual(body.value as? String, "Original body")
        replaceText(in: title, with: "Edited snippet")
        replaceText(in: body, with: "Edited body remains private until revealed")
        replaceText(in: app.textFields["snippetTags"], with: "edited, reusable")
        keepScreenshot(of: app, name: "Snippet editor")
        app.buttons["saveSnippet"].click()

        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        let reveal = app.buttons["revealClipboardContent"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Edited body remains private until revealed"].exists)
        reveal.click()
        XCTAssertTrue(app.staticTexts["Edited body remains private until revealed"].waitForExistence(timeout: 5))

        // The updated tag must participate in the same metadata search used by
        // the main list, so title/body/tag editing is verified end to end.
        let search = app.textFields["historySearch"]
        replaceText(in: search, with: "#reusable")
        XCTAssertTrue(app.staticTexts["Edited snippet"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No clipboard items"].exists)
    }

    @MainActor
    func testQuickCopySupportsSearchArrowSelectionReturnAndEscape() throws {
        let app = launchIsolatedApplication()
        createSnippet(in: app, title: "Alpha picker test", body: "First test content", tags: "")
        createSnippet(in: app, title: "Beta picker test", body: "Second test content", tags: "")

        // The isolated app does not register the global hotkey. Its ordinary
        // application menu command has the same shortcut and opens the panel.
        app.typeKey("v", modifierFlags: [.command, .option])
        let search = app.searchFields["QuickClipboardSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        // Type without clicking first: this also verifies autofocus.
        app.typeText("picker test")
        XCTAssertEqual(search.value as? String, "picker test")
        let alpha = app.buttons["Copy Alpha picker test"]
        let beta = app.buttons["Copy Beta picker test"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertTrue(beta.exists)
        XCTAssertTrue(beta.isSelected)
        search.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(alpha.isSelected)
        search.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))

        app.typeKey("v", modifierFlags: [.command, .option])
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "")
        search.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func launchIsolatedApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["COPARE_UI_TESTS"] = "1"
        app.launch()
        XCTAssertTrue(app.windows["CoPaRe"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, name: String) {
        // XCUIApplication.screenshot() captures the desktop on macOS. Restrict
        // evidence to the test window so other applications are never attached.
        let window = app.windows["CoPaRe"]
        XCTAssertTrue(window.exists)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func createSnippet(in app: XCUIApplication, title: String, body: String, tags: String) {
        app.buttons["newSnippet"].click()
        let titleField = app.textFields["snippetTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        replaceText(in: titleField, with: title)
        replaceText(in: app.textViews["snippetBody"], with: body)
        if !tags.isEmpty {
            replaceText(in: app.textFields["snippetTags"], with: tags)
        }
        app.buttons["saveSnippet"].click()
        XCTAssertTrue(titleField.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        let app = XCUIApplication()
        app.launchEnvironment["COPARE_UI_TESTS"] = "1"
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
