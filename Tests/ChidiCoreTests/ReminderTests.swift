import XCTest
@testable import ChidiCore

final class ReminderTests: XCTestCase {
    func testPlanKeepsKindsAndRoutesIndependent() throws {
        let person = Person(name: "甲")
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        let ordinary = Reminder(amount: 2, unit: .hours)
        let strong = Reminder(amount: 1, unit: .days, kind: .strong)
        let personal = Reminder(amount: 5, unit: .minutes)
        let step = TaskStep(title: "核对", assignments: [Assignment(personID: person.id, deadline: Deadline(date: date, reminders: [personal]))])
        let task = ChidiTask(title: "报价", deadline: Deadline(date: date, reminders: [ordinary, strong]), steps: [step])
        var doc = ChidiDocument(); doc.tasks = [task]; doc.people = [person]
        try doc.validate()
        let plan = doc.reminderPlan()
        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan.first?.id, strong.id)
        XCTAssertEqual(plan.first?.fireDate, date.addingTimeInterval(-86400))
        let routed = try XCTUnwrap(plan.first { $0.id == personal.id })
        XCTAssertEqual(routed.stepID, step.id)
        XCTAssertEqual(routed.personID, person.id)
        XCTAssertEqual(routed.taskID, task.id)
        XCTAssertEqual(routed.detail, "个人 DDL · 甲")
    }

    func testDateOnlyAnchorIgnoresHiddenTimeWithoutChangingDeadline() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 28800)!
        let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 2))!
        let deadline = Deadline(date: morning, includesTime: false, reminders: [Reminder(amount: 1, unit: .hours)])
        var doc = ChidiDocument(); doc.tasks = [ChidiTask(title: "日期", deadline: deadline)]
        XCTAssertEqual(cal.component(.hour, from: doc.reminderPlan(calendar: cal)[0].fireDate), 8)
        XCTAssertEqual(doc.tasks[0].deadline, deadline)
    }

    func testCompletingArchivingAndDeletingRemoveScheduledWork() {
        let deadline = Deadline(date: .now, reminders: [Reminder(amount: 0, unit: .minutes)])
        let board = TaskBoard(title: "项目")
        var doc = ChidiDocument(); doc.boards = [board]
        doc.tasks = [ChidiTask(title: "事", boardID: board.id, deadline: deadline)]
        XCTAssertEqual(doc.reminderPlan().count, 1)
        doc.tasks[0].status = .completed; XCTAssertTrue(doc.reminderPlan().isEmpty)
        doc.tasks[0].status = nil; doc.boards[0].archivedAt = .now; XCTAssertTrue(doc.reminderPlan().isEmpty)
        doc.boards[0].archivedAt = nil; doc.boards[0].deletedAt = .now; XCTAssertTrue(doc.reminderPlan().isEmpty)
        doc.boards[0].deletedAt = nil; doc.tasks[0].deletedAt = .now; XCTAssertTrue(doc.reminderPlan().isEmpty)
    }
}
