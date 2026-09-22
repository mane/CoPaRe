//
//  CoPaReUITestsLaunchTests.swift
//  CoPaReUITests
//
//  Created by CoPaRe contributors.
//

import XCTest

final class CoPaReUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["COPARE_UI_TESTS"] = "1"
        app.launch()
        XCTAssertTrue(app.windows["CoPaRe"].waitForExistence(timeout: 5))

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
