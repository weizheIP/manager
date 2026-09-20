import AppIntents
import Foundation
import Observation

struct AppEntryRequest: Identifiable {
    enum Destination { case capture(String, UUID?, Bool), detail(UUID) }
    let id = UUID()
    let destination: Destination
}

@MainActor @Observable
final class AppEntryRouter {
    static let shared = AppEntryRouter()
    var pending: [AppEntryRequest] = []
    func enqueue(_ destination: AppEntryRequest.Destination) { pending.append(AppEntryRequest(destination: destination)) }
}

nonisolated struct TaskBoardEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "任务栏"
    static let defaultQuery = TaskBoardQuery()
    let id: String
    var name: String
    var position: Int

    init(id: UUID, name: String, position: Int) {
        self.id = id.uuidString
        self.name = name
        self.position = position
    }

    var boardID: UUID? { UUID(uuidString: id) }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "第 \(position) 个任务栏") }
}

nonisolated struct TaskBoardQuery: EntityStringQuery {
    @MainActor private func available() throws -> [TaskBoardEntity] {
        guard !TaskStore.shared.isReadOnly else { throw ChidiDataError.invalid("本地数据读取失败，无法获取任务栏。") }
        return TaskStore.shared.document.activeBoards.enumerated().map { TaskBoardEntity(id: $0.element.id, name: $0.element.title, position: $0.offset + 1) }
    }
    @MainActor func entities(for identifiers: [String]) async throws -> [TaskBoardEntity] { try available().filter { identifiers.contains($0.id) } }
    @MainActor func entities(matching string: String) async throws -> [TaskBoardEntity] { try available().filter { $0.name.localizedStandardContains(string) } }
    @MainActor func suggestedEntities() async throws -> [TaskBoardEntity] { try available() }
}

struct SmartCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "记任务"
    static var description = IntentDescription("输入一句话，在次第中解析并预览，确认后创建任务。")
    static var supportedModes: IntentModes = .foreground(.immediate)
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "任务内容", requestValueDialog: "要用次第记下什么任务？") var content: String
    static var parameterSummary: some ParameterSummary { Summary("用次第解析并预览\(\.$content)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ChidiDataError.invalid("任务内容不能为空。") }
        AppEntryRouter.shared.enqueue(.capture(text, nil, true))
        return .result(dialog: "请在次第中核对解析结果，确认后添加。")
    }
}

struct BoardCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "往任务栏记任务"
    static var description = IntentDescription("先选择任务栏，再输入任务内容并在次第中核对。")
    static var supportedModes: IntentModes = .foreground(.immediate)
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "任务栏", requestValueDialog: "要放到哪个任务栏？", requestDisambiguationDialog: "有同名任务栏，请选择一个。") var board: TaskBoardEntity
    @Parameter(title: "任务内容", requestValueDialog: "要在这个任务栏记下什么？") var content: String
    static var parameterSummary: some ParameterSummary { Summary("往\(\.$board)记任务\(\.$content)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let boardID = board.boardID,
              TaskStore.shared.document.activeBoards.contains(where: { $0.id == boardID }) else {
            throw ChidiDataError.invalid("这个任务栏已归档或删除，请重新选择。")
        }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ChidiDataError.invalid("任务内容不能为空。") }
        AppEntryRouter.shared.enqueue(.capture(text, boardID, true))
        return .result(dialog: "已打开任务创建卡片，请核对后添加。")
    }
}

struct QuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "记一下"
    static var description = IntentDescription("将原话作为任务名称直接保存到未分类，不设置其他字段。")
    static var supportedModes: IntentModes = .foreground(.immediate)
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "任务内容", requestValueDialog: "要记下什么？") var content: String
    static var parameterSummary: some ParameterSummary { Summary("直接记下\(\.$content)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ChidiDataError.invalid("任务名称不能为空。") }
        let task = ChidiTask(title: title)
        guard TaskStore.shared.saveTask(task) else { throw ChidiDataError.invalid(TaskStore.shared.errorMessage ?? "任务未保存，请重试。") }
        AppEntryRouter.shared.enqueue(.detail(task.id))
        return .result(dialog: "已记到次第的未分类任务。")
    }
}

nonisolated struct ChidiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SmartCaptureIntent(), phrases: ["用\(.applicationName)记任务"], shortTitle: "记任务", systemImageName: "sparkles")
        AppShortcut(intent: BoardCaptureIntent(), phrases: ["用\(.applicationName)往\(\.$board)记任务", "用\(.applicationName)往任务栏记任务"], shortTitle: "往任务栏记", systemImageName: "folder.badge.plus")
        AppShortcut(intent: QuickCaptureIntent(), phrases: ["用\(.applicationName)记一下"], shortTitle: "记一下", systemImageName: "square.and.pencil")
    }
    static var shortcutTileColor: ShortcutTileColor = .purple
}
