import XCTest

final class AdaptiveLoginTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_SG"]
    }

    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testLandscapeCanReachSignInAndPrivacySheet() {
        app.launch()
        XCTAssertTrue(app.textFields["you@example.com"].waitForExistence(timeout: 10),
                      "Run layout tests on a signed-out simulator.")
        XCUIDevice.shared.orientation = .landscapeLeft
        reveal(app.buttons["Privacy Notice"])
        XCTAssertTrue(app.buttons["Sign In"].exists)
        app.buttons["Privacy Notice"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(app.buttons["Privacy Notice"].waitForExistence(timeout: 5))
    }

    func testEmailSurvivesRotationWithKeyboard() {
        app.launch()
        let email = app.textFields["you@example.com"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("layout-check@example.invalid")
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertEqual(email.value as? String, "layout-check@example.invalid")
        email.typeText("\n")
        let passwordField = app.secureTextFields["Password"]
        passwordField.typeText("layout-only")
        passwordField.typeText("\n")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(email.value as? String, "layout-check@example.invalid")
        reveal(app.buttons["Sign In"])
        XCTAssertTrue(app.buttons["Sign In"].isEnabled)
    }

    func testAccessibilityTextCanReachPrivacy() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.textFields["you@example.com"].waitForExistence(timeout: 10))
        reveal(app.buttons["Privacy Notice"])
        app.buttons["Privacy Notice"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if element.isHittable && app.windows.firstMatch.frame.contains(element.frame) { return }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Control must remain reachable by scrolling", file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame), file: file, line: line)
    }
}
