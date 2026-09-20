import Foundation

/// All-or-nothing file replacement. Decoding never falls back to an empty document on errors.
struct DocumentRepository {
    let url: URL

    func load() throws -> ChidiDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return ChidiDocument() }
        let data = try Data(contentsOf: url)
        let header = try JSONDecoder().decode(VersionHeader.self, from: data)
        guard header.schemaVersion == ChidiDocument.currentVersion else {
            throw ChidiDataError.unsupportedVersion(header.schemaVersion)
        }
        let document = try JSONDecoder().decode(ChidiDocument.self, from: data)
        try document.validate()
        return document
    }

    func save(_ document: ChidiDocument) throws {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private struct VersionHeader: Decodable { var schemaVersion: Int }
}
