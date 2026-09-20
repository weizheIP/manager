import Foundation
import Observation

@MainActor @Observable
final class TaskStore {
    private(set) var document = ChidiDocument()
    private(set) var isReadOnly = false
    var errorMessage: String?
    private let repository: DocumentRepository
    let attachmentStorage: AttachmentStorage

    init(url: URL? = nil) {
        let location = url ?? URL.applicationSupportDirectory.appending(path: "Chidi/tasks-v1.json")
        repository = DocumentRepository(url: location)
        attachmentStorage = AttachmentStorage(directory: location.deletingLastPathComponent().appending(path: "Attachments"))
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
        if !isReadOnly {
            do { try attachmentStorage.removeUnreferenced(keeping: Set(document.attachments.map(\.relativePath))) }
            catch { errorMessage = "数据已读取，部分附件缓存未能清理：\(error.localizedDescription)" }
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
            let removed = Set(document.attachments.map(\.relativePath)).subtracting(candidate.attachments.map(\.relativePath))
            document = candidate
            for path in removed {
                do { try attachmentStorage.remove(path) }
                catch { errorMessage = "数据已保存，部分过期附件未能清理，将在下次启动时重试。" }
            }
            return true
        } catch {
            errorMessage = "未能保存，原数据未改变。\n\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveTask(_ task: ChidiTask) -> Bool {
        change { $0.upsertTask(task) }
    }

    func task(_ id: UUID) -> ChidiTask? { document.tasks.first { $0.id == id } }
}
