// UI tests for the iPhone app. Verifies long-press drag both reorders rows
// within a section and moves a row directly into another status section.
import XCTest

final class PeekabooMobileUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PEEKABOO_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 3)
        app = nil
    }

    func testDragReordersWithinSection() throws {
        addTask(named: "Alpha")
        addTask(named: "Beta")

        let first = app.staticTexts["Alpha"]
        let second = app.staticTexts["Beta"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        // Newest first: Beta sits above Alpha.
        XCTAssertLessThan(second.frame.minY, first.frame.minY)

        second.press(forDuration: 1.0, thenDragTo: first)

        let deadline = Date().addingTimeInterval(3)
        while second.frame.minY <= first.frame.minY, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThan(second.frame.minY, first.frame.minY)
        // Dropping into the last slot of To Do is a reorder. It used to read as
        // the Done edge zone and completed the task instead, which still moved
        // the row below its neighbour and passed the check above.
        XCTAssertEqual(app.staticTexts["task-section-todo"].label, "To do · 2")
        XCTAssertFalse(app.staticTexts["task-section-done"].exists)
    }

    func testDragMovesTaskAcrossSections() throws {
        addTask(named: "Move me")

        let draggedTask = app.staticTexts["Move me"]
        let destination = app.otherElements["task-edge-inProgress"]
        XCTAssertTrue(draggedTask.waitForExistence(timeout: 3))
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["task-section-inProgress"].exists)
        XCTAssertFalse(app.staticTexts["task-section-done"].exists)
        draggedTask.press(
            forDuration: 1.2,
            thenDragTo: destination,
            withVelocity: .slow,
            thenHoldForDuration: 0.6
        )

        let todoSection = app.staticTexts["task-section-todo"]
        let inProgressSection = app.staticTexts["task-section-inProgress"]
        let inProgressHasTask = expectation(
            for: NSPredicate(format: "label CONTAINS '1'"),
            evaluatedWith: inProgressSection
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [inProgressHasTask], timeout: 4),
            .completed
        )
        XCTAssertTrue(todoSection.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Move me"].exists)

        let doneDestination = app.otherElements["task-edge-done"]
        XCTAssertTrue(doneDestination.waitForExistence(timeout: 3))
        app.staticTexts["Move me"].press(
            forDuration: 1.2,
            thenDragTo: doneDestination,
            withVelocity: .slow,
            thenHoldForDuration: 0.6
        )
        XCTAssertTrue(app.staticTexts["task-section-done"].waitForExistence(timeout: 4))
        XCTAssertTrue(inProgressSection.waitForNonExistence(timeout: 3))

        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "iPhone cross-section drag"
        proof.lifetime = .keepAlways
        add(proof)
    }

    func testDoubleTapMovesTaskToInProgress() throws {
        addTask(named: "Toggle me")

        let title = app.staticTexts["Toggle me"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.doubleTap()

        let inProgressSection = app.staticTexts["task-section-inProgress"]
        XCTAssertTrue(inProgressSection.waitForExistence(timeout: 3))
    }

    func testSearchFiltersTasksByTitle() throws {
        addTask(named: "Alpha task")
        addTask(named: "Beta task")

        let searchField = app.textFields["task-search-field"]
        XCTAssertFalse(searchField.exists)

        let searchButton = app.buttons["toggle-task-search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 3))
        searchButton.tap()

        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.typeText("ALPHA")
        XCTAssertTrue(app.staticTexts["Alpha task"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Beta task"].waitForNonExistence(timeout: 3))

        let clearButton = app.buttons["clear-task-search"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3))
        clearButton.tap()
        XCTAssertTrue(app.staticTexts["Beta task"].waitForExistence(timeout: 3))

        searchField.typeText("Missing task")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Try a different search."].exists)

        searchButton.tap()
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Alpha task"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Beta task"].exists)
    }

    private func addTask(named title: String, priority: String? = nil) {
        let addButton = app.buttons["add-task-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()

        let titleField = app.textViews["task-title-field"].exists
            ? app.textViews["task-title-field"]
            : app.textFields["task-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.typeText(title)

        if let priority {
            let chip = app.buttons["\(priority) priority"]
            XCTAssertTrue(chip.waitForExistence(timeout: 3))
            chip.tap()
        }

        let saveButton = app.buttons["save-task"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
    }
}
