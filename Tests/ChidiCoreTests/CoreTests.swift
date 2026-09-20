import XCTest
@testable import ChidiCore

final class CoreTests: XCTestCase {
    func testNameOnlyTaskAndOrderingSurviveDiskRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = DocumentRepository(url: folder.appendingPathComponent("data.json"))
        var doc = ChidiDocument()
        let first = ChidiTask(title: "第一件事")
        let second = ChidiTask(title: "第二件事")
        doc.tasks = [second, first]
        try repo.save(doc)
        let restored = try repo.load()
        XCTAssertEqual(restored, doc)
        XCTAssertNil(restored.tasks[0].status)
        XCTAssertNil(restored.tasks[0].deadline)
        XCTAssertTrue(restored.tasks[0].assignments.isEmpty)
    }

    func testRejectedWritePreservesPriorDocument() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = DocumentRepository(url: folder.appendingPathComponent("data.json"))
        var valid = ChidiDocument()
        valid.tasks = [ChidiTask(title: "原始任务")]
        try repo.save(valid)
        var invalid = valid
        invalid.tasks[0].title = "  \n"
        XCTAssertThrowsError(try repo.save(invalid))
        XCTAssertEqual(try repo.load(), valid)
    }

    func testCorruptOrFutureDataIsNotSilentlyReplaced() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = DocumentRepository(url: folder.appendingPathComponent("data.json"))
        for text in ["not json", "{\"schemaVersion\":999}"] {
            let original = Data(text.utf8)
            try original.write(to: repo.url)
            XCTAssertThrowsError(try repo.load())
            XCTAssertEqual(try Data(contentsOf: repo.url), original)
        }
    }

    func testThreeDeadlineKindsAndMultipleIndependentAssignments() throws {
        let alice = Person(name: "同名"), bob = Person(name: "同名")
        let when = Date(timeIntervalSince1970: 1800000000)
        var task = ChidiTask(title: "报价")
        task.deadline = Deadline(date: when)
        task.assignments = [Assignment(personID: alice.id, deadline: Deadline(date: when)), Assignment(personID: bob.id)]
        task.steps = [TaskStep(title: "核对", deadline: Deadline(date: when))]
        var doc = ChidiDocument()
        doc.people = [alice, bob]; doc.tasks = [task]
        try doc.validate()
        XCTAssertEqual(Set(doc.deadlineOccurrences().map(\.kind)), Set([.task, .step, .person]))
        XCTAssertEqual(Set(doc.deadlineOccurrences().map(\.id)).count, 3)
        XCTAssertNil(doc.tasks[0].assignments[1].deadline)
    }

    func testDependencyWarningDoesNotBlockStartingOrCompleteParent() throws {
        let first = TaskStep(title: "前置")
        var second = TaskStep(title: "后续", predecessorIDs: [first.id])
        var task = ChidiTask(title: "项目", steps: [first, second])
        XCTAssertEqual(task.unfinishedPredecessors(of: second).map(\.id), [first.id])
        second.status = .active
        task.steps[1] = second
        var doc = ChidiDocument(); doc.tasks = [task]
        XCTAssertNoThrow(try doc.validate())
        task.steps[0].status = .completed; task.steps[1].status = .completed
        XCTAssertTrue(task.allStepsCompleted)
        XCTAssertNil(task.status)
        task.removeStep(first.id)
        XCTAssertTrue(task.steps[0].predecessorIDs.isEmpty)
    }

    func testCyclesRejected() {
        var a = TaskStep(title: "A"), b = TaskStep(title: "B")
        a.predecessorIDs = [b.id]; b.predecessorIDs = [a.id]
        var doc = ChidiDocument(); doc.tasks = [ChidiTask(title: "任务", steps: [a,b])]
        XCTAssertThrowsError(try doc.validate())
    }

    func testOverdueDoesNotMutateDecisions() {
        let date = Date(timeIntervalSince1970: 100000)
        let task = ChidiTask(title: "事", quadrant: .important, status: .waiting, deadline: Deadline(date: date))
        let before = task
        XCTAssertEqual(task.deadline?.overdueDescription(at: date.addingTimeInterval(7200)), "已过 DDL 2 小时")
        XCTAssertEqual(task, before)
    }

    func testArchivedSearchAndTrashBoundary() throws {
        let now = Date(timeIntervalSince1970: 1800000000)
        var task = ChidiTask(title: "报价", archivedAt: now)
        let person = Person(name: "张三", tags: ["设计"])
        task.assignments = [Assignment(personID: person.id)]
        var doc = ChidiDocument(); doc.people = [person]; doc.tasks = [task]
        XCTAssertTrue(doc.activeTasks.isEmpty)
        XCTAssertEqual(doc.searchTasks("设计").map(\.id), [task.id])
        doc.tasks[0].deletedAt = now
        XCTAssertTrue(doc.searchTasks("报价").isEmpty)
        _ = doc.purgeExpired(at: now.addingTimeInterval(29 * 86400))
        XCTAssertEqual(doc.tasks.count, 1)
        _ = doc.purgeExpired(at: now.addingTimeInterval(30 * 86400))
        XCTAssertTrue(doc.tasks.isEmpty)
    }

    func testRestoreOneTaskDoesNotRestoreWholeDeletedBoard() {
        let board = TaskBoard(title: "项目", deletedAt: .now)
        let a = ChidiTask(title: "恢复我", boardID: board.id)
        let b = ChidiTask(title: "保留删除", boardID: board.id)
        var doc = ChidiDocument(); doc.boards = [board]; doc.tasks = [a,b]
        doc.restoreTask(a.id)
        XCTAssertNil(doc.tasks[0].boardID)
        XCTAssertFalse(doc.isDeleted(doc.tasks[0]))
        XCTAssertTrue(doc.isDeleted(doc.tasks[1]))
        XCTAssertNotNil(doc.boards[0].deletedAt)
    }

    func testRemindersRemainIndependentAfterEncoding() throws {
        let ddl = Deadline(date: .now, reminders: [Reminder(amount: 2, unit: .hours, kind: .strong), Reminder(amount: 1, unit: .days)])
        let recovered = try JSONDecoder().decode(Deadline.self, from: JSONEncoder().encode(ddl))
        XCTAssertEqual(recovered, ddl)
        XCTAssertEqual(recovered.reminders[0].fireDate(for: ddl.date), ddl.date.addingTimeInterval(-7200))
        XCTAssertEqual(recovered.reminders[1].kind, .ordinary)
    }
}
