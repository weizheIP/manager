import Foundation
import Observation

@MainActor @Observable
final class TaskStore {
    private(set) var document = ChidiDocument()
    private(set) var isReadOnly = false
    var errorMessage: String?
    private let repository: DocumentRepository

    init(url: URL? = nil) {
        let location = url ?? URL.applicationSupportDirectory.appending(path: "Chidi/tasks-v1.json")
        repository = DocumentRepository(url: location)
        do {
            document = try repository.load()
            var cleaned = document
            _ = cleaned.purgeExpired()
            if cleaned != document {
                try repository.save(cleaned)
                document = cleaned
            }
        } catch {
            isReadOnly = true
            errorMessage = "无法读取本地数据，原文件已保留，暂不允许写入。\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    func change(_ edit: (inout ChidiDocument) throws -> Void) -> Bool {
        guard !isReadOnly else {
            errorMessage = "本地数据尚未成功读取，不能覆盖原文件。"
            return false
        }
        do {
            var candidate = document
            try edit(&candidate)
            _ = candidate.purgeExpired()
            try repository.save(candidate)
            document = candidate
            return true
        } catch {
            errorMessage = "未能保存，原数据未改变。\n\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveTask(_ task: ChidiTask) -> Bool {
        change { doc in
            var task = task
            task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            task.updatedAt = .now
            if let index = doc.tasks.firstIndex(where: { $0.id == task.id }) { doc.tasks[index] = task }
            else { doc.tasks.append(task) }
            if let index = doc.boards.firstIndex(where: { $0.id == task.boardID }) { doc.boards[index].updatedAt = .now }
        }
    }

    func task(_ id: UUID) -> ChidiTask? { document.tasks.first { $0.id == id } }
}
