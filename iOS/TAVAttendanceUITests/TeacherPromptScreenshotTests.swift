import XCTest

final class TeacherPromptScreenshotTests: XCTestCase {
    func testLightAndDarkTeacherFlow() {
        continueAfterFailure = false
        for theme in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["--teacher-prompts-demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_SG"]
            if theme == "dark" { app.launchArguments.append("--teacher-prompts-dark") }
            app.launch()
            let lesson = app.buttons["teacher.lesson.40000000-0000-4000-8000-000000000001"]
            XCTAssertTrue(lesson.waitForExistence(timeout: 15))
            capture(app, "\(theme)-01-lessons")
            lesson.tap()
            let all = app.buttons["teacher.allPresent"]
            XCTAssertTrue(all.waitForExistence(timeout: 10))
            capture(app, "\(theme)-02-attendance")
            all.tap()
            let submit = app.buttons["teacher.submit"]
            XCTAssertTrue(submit.waitForExistence(timeout: 10))
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: submit)
            waitForExpectations(timeout: 10)
            capture(app, "\(theme)-03-all-present")
            reveal(app.buttons["teacher.snooze"], in: app)
            app.buttons["teacher.snooze"].tap()
            reveal(app.buttons["teacher.confirmSnooze"], in: app, up: false)
            XCTAssertTrue(app.staticTexts["teacher.snoozeConfirmation"].exists)
            capture(app, "\(theme)-04-snooze-confirmation")
            app.buttons["teacher.confirmSnooze"].tap()
            reveal(submit, in: app)
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: submit)
            waitForExpectations(timeout: 10)
            submit.tap()
            let done = app.descendants(matching: .any)["teacher.submitted"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 10))
            reveal(done, in: app, up: false)
            capture(app, "\(theme)-05-submitted")
            app.terminate()
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<10 {
            if element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }
}
