import Foundation
import UniformTypeIdentifiers

extension TaskStore {
    func attachmentURL(_ attachment: AttachmentRecord) throws -> URL {
        let url = try attachmentStorage.url(for: attachment.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ChidiDataError.invalid("附件文件找不到，原记录已保留。") }
        return url
    }

    /// File work is off the UI thread; the latest document is revalidated before committing the record.
    func importAttachment(from source: URL, taskID: UUID, stepID: UUID?, kind: AttachmentRecord.Kind? = nil, filename: String? = nil) async -> Bool {
        guard !isReadOnly else { errorMessage = "本地数据尚未成功读取，不能添加附件。"; return false }
        let id = UUID(), storage = attachmentStorage
        do {
            let path = try await Task.detached(priority: .userInitiated) {
                let accessed = source.startAccessingSecurityScopedResource()
                defer { if accessed { source.stopAccessingSecurityScopedResource() } }
                var coordinateError: NSError?
                var outcome: Result<String, Error>?
                NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinateError) { readable in
                    outcome = Result { try storage.importFile(readable, id: id) }
                }
                if let coordinateError { throw coordinateError }
                guard let outcome else { throw ChidiDataError.invalid("文件暂时无法读取，请稍后重试。") }
                return try outcome.get()
            }.value
            let contentType = UTType(filenameExtension: source.pathExtension)
            let resolvedKind: AttachmentRecord.Kind = kind ?? (contentType?.conforms(to: .image) == true ? .image : contentType?.conforms(to: .audio) == true ? .audio : .file)
            let record = AttachmentRecord(id: id, taskID: taskID, stepID: stepID, filename: filename ?? source.lastPathComponent, relativePath: path, kind: resolvedKind)
            let saved = change { doc in
                guard let task = doc.tasks.first(where: { $0.id == taskID }), !doc.isDeleted(task), stepID == nil || task.steps.contains(where: { $0.id == stepID }) else {
                    throw ChidiDataError.invalid("原任务或步骤已被删除，附件未添加。")
                }
                doc.attachments.append(record)
            }
            if !saved { try? storage.remove(path) }
            return saved
        } catch { errorMessage = "附件未添加：\(error.localizedDescription)"; return false }
    }
}
