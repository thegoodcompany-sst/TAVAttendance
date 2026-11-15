import XCTest

final class TeacherPromptScreenshotTests: XCTestCase {
    // Separate cases ensure a failure in one appearance does not skip the other.
    func testLightTeacherFlow() { runTeacherFlow(theme: "light") }
    func testDarkTeacherFlow() { runTeacherFlow(theme: "dark") }

    private func runTeacherFlow(theme: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--teacher-prompts-demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_SG"]
        if theme == "dark" { app.launchArguments.append("--teacher-prompts-dark") }
        app.launch()
        defer { app.terminate() }
        let lesson = app.buttons["teacher.lesson.40000000-0000-4000-8000-000000000001"]
        waitUntilReady(lesson)
        capture(app, "\(theme)-01-lessons")
        lesson.tap()
        // First prove navigation resolved; scrolling cannot repair a failed route.
        waitUntilReady(app.buttons["teacher.back"])
        let all = app.buttons["teacher.allPresent"]
        reveal(all, in: app)
        waitUntilReady(all)
        capture(app, "\(theme)-02-attendance")
        all.tap()
        let review = app.staticTexts["teacher.allPresentReview"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        capture(app, "\(theme)-03-all-present")

        let snooze = app.buttons["teacher.snooze"]
        reveal(snooze, in: app)
        waitUntilReady(snooze)
        snooze.tap()
        let confirmation = app.buttons["teacher.confirmSnooze"]
        reveal(confirmation, in: app, up: false)
        waitUntilReady(confirmation)
        XCTAssertTrue(app.staticTexts["teacher.snoozeConfirmation"].exists)
        capture(app, "\(theme)-04-snooze-confirmation")
        confirmation.tap()
        let snoozed = app.staticTexts["teacher.snoozed"]
        XCTAssertTrue(snoozed.waitForExistence(timeout: 10))
        reveal(snoozed, in: app, up: false)
        XCTAssertFalse(confirmation.exists)
        capture(app, "\(theme)-05-after-snooze")

        let submit = app.buttons["teacher.submit"]
        reveal(submit, in: app)
        waitUntilReady(submit)
        submit.tap()
        let done = app.descendants(matching: .any)["teacher.submitted"].firstMatch
        reveal(done, in: app, up: false)
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["teacher.submit"].exists)
        capture(app, "\(theme)-06-submitted")
    }

    private func waitUntilReady(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"),
            object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, file: file, line: line)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        let list = app.collectionViews["teacher.attendanceList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), file: file, line: line)
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            // Short drags within the list avoid pulling the sheet's dismissal handle.
            let upper = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let lower = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            if up { lower.press(forDuration: 0.05, thenDragTo: upper) }
            else { upper.press(forDuration: 0.05, thenDragTo: lower) }
        }
        waitUntilReady(element, file: file, line: line)
    }
}
