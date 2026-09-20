import XCTest
@testable import ChidiCore

final class AttachmentTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testImportCopiesBytesAndDoesNotCollideForSameFilename() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("报价.txt")
        let original = Data("首版报价".utf8); try original.write(to: source)
        let storage = AttachmentStorage(directory: root.appendingPathComponent("private"))
        let first = try storage.importFile(source, id: UUID())
        try Data("第二版".utf8).write(to: source)
        let second = try storage.importFile(source, id: UUID())
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: storage.url(for: first)), original)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(String(data: try Data(contentsOf: storage.url(for: second)), encoding: .utf8), "第二版")
    }

    func testRejectsTraversalAndEscapingSymlinks() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let inside = root.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let storage = AttachmentStorage(directory: inside)
        for path in ["", ".", "..", "../data.json", "/tmp/file", "sub/file", "a\\b"] { XCTAssertThrowsError(try storage.url(for: path)) }
        let original = root.appendingPathComponent("original.txt"); try Data("保留".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: inside.appendingPathComponent("link.txt"), withDestinationURL: original)
        XCTAssertThrowsError(try storage.remove("link.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testLimitAndDuplicateIDNeverOverwriteStoredFile() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("small.bin"); try Data([1,2,3]).write(to: source)
        let storage = AttachmentStorage(directory: root.appendingPathComponent("files"))
        let id = UUID(); let path = try storage.importFile(source, id: id)
        try Data([9]).write(to: source)
        XCTAssertThrowsError(try storage.importFile(source, id: id))
        XCTAssertEqual(try Data(contentsOf: storage.url(for: path)), Data([1,2,3]))
        let huge = root.appendingPathComponent("huge.bin"); FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge); try handle.truncate(atOffset: UInt64(AttachmentStorage.maximumBytes + 1)); try handle.close()
        XCTAssertThrowsError(try storage.importFile(huge, id: UUID()))
        XCTAssertThrowsError(try storage.importFile(root, id: UUID()))
    }

    func testAttachmentSearchTrashRestoreAndThirtyDayCleanup() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let task = ChidiTask(title: "报价")
        let record = AttachmentRecord(taskID: task.id, filename: "合同.pdf", relativePath: UUID().uuidString + ".pdf", kind: .file)
        var doc = ChidiDocument(); doc.tasks = [task]; doc.attachments = [record]
        XCTAssertEqual(doc.searchTasks("合同").count, 1)
        doc.attachments[0].deletedAt = now
        XCTAssertTrue(doc.searchTasks("合同").isEmpty)
        XCTAssertTrue(doc.purgeExpired(at: now.addingTimeInterval(29*86400)).isEmpty)
        doc.attachments[0].deletedAt = nil
        XCTAssertEqual(doc.searchTasks("合同").count, 1)
        doc.tasks[0].deletedAt = now
        XCTAssertTrue(doc.purgeExpired(at: now.addingTimeInterval(29*86400)).isEmpty)
        doc.restoreTask(task.id)
        XCTAssertEqual(doc.attachments.count, 1)
        doc.tasks[0].deletedAt = now
        XCTAssertEqual(doc.purgeExpired(at: now.addingTimeInterval(31*86400)), [record.relativePath])
        XCTAssertTrue(doc.attachments.isEmpty)
    }

    func testCrashCleanupKeepsReferencedFilesAndUnrelatedFiles() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let storage = AttachmentStorage(directory: root)
        let kept = UUID().uuidString + ".txt", abandoned = UUID().uuidString + ".txt"
        for path in [kept, abandoned, "readme.txt"] { try Data([1]).write(to: root.appendingPathComponent(path)) }
        try storage.removeUnreferenced(keeping: [kept])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(kept).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(abandoned).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("readme.txt").path))
    }

    func testRemovingStepMovesItsAttachmentsToRecoverableTaskTrash() throws {
        let step = TaskStep(title: "步骤")
        var task = ChidiTask(title: "事", steps: [step])
        let file = AttachmentRecord(taskID: task.id, stepID: step.id, filename: "材料.txt", relativePath: "material.txt", kind: .file)
        var doc = ChidiDocument(); doc.tasks = [task]; doc.attachments = [file]
        task.removeStep(step.id)
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        doc.upsertTask(task, at: now)
        try doc.validate()
        XCTAssertNil(doc.attachments[0].stepID)
        XCTAssertEqual(doc.attachments[0].deletedAt, now)
        XCTAssertTrue(doc.purgeExpired(at: now.addingTimeInterval(29 * 86400)).isEmpty)
        doc.attachments[0].deletedAt = nil
        XCTAssertEqual(doc.searchTasks("材料").count, 1)
    }

    func testOlderSchemaOneAttachmentWithoutDeletionDateDecodes() throws {
        var doc = ChidiDocument(); let task = ChidiTask(title: "旧任务"); doc.tasks = [task]
        doc.attachments = [AttachmentRecord(taskID: task.id, filename: "旧文件.txt", relativePath: "old.txt", kind: .file)]
        let bytes = try JSONEncoder().encode(doc)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("deletedAt"))
        let decoded = try JSONDecoder().decode(ChidiDocument.self, from: bytes)
        try decoded.validate()
        XCTAssertNil(decoded.attachments[0].deletedAt)
    }
}
