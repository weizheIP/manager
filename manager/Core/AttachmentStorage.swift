import Foundation

/// Private files are separate from document records; callers commit records only after import succeeds.
struct AttachmentStorage: Sendable {
    nonisolated static let maximumBytes = 100 * 1024 * 1024
    let directory: URL
    nonisolated init(directory: URL) { self.directory = directory }

    nonisolated func url(for relativePath: String) throws -> URL {
        guard Self.isSafePath(relativePath) else { throw ChidiDataError.invalid("附件路径无效。") }
        let result = directory.appendingPathComponent(relativePath)
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard result.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else {
            throw ChidiDataError.invalid("附件不能指向存储目录之外。")
        }
        return result
    }

    nonisolated static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty && path != "." && path != ".." && !path.contains("/") && !path.contains("\\")
    }

    nonisolated func importFile(_ source: URL, id: UUID) throws -> String {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ChidiDataError.invalid("请选择文件，暂不支持文件夹。") }
        guard let size = values.fileSize, size <= Self.maximumBytes else { throw ChidiDataError.invalid("单个附件不能超过 100 MB。") }
        let ext = source.pathExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(16)
        let relative = id.uuidString + (ext.isEmpty ? "" : "." + ext)
        let target = try url(for: relative)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw ChidiDataError.invalid("附件标识重复，请重新添加。") }
        do {
            try FileManager.default.copyItem(at: source, to: target)
            // Recheck after copying if a provider changed the file while it was read.
            let copiedSize = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard copiedSize <= Self.maximumBytes else { throw ChidiDataError.invalid("单个附件不能超过 100 MB。") }
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
            #endif
            return relative
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    nonisolated func remove(_ relativePath: String) throws {
        let target = try url(for: relativePath)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }

    /// Clean imports interrupted before commit. Called only after a document was read successfully.
    nonisolated func removeUnreferenced(keeping paths: Set<String>) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                  !paths.contains(file.lastPathComponent) else { continue }
            try remove(file.lastPathComponent)
        }
    }
}
