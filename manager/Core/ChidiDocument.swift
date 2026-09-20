import Foundation

enum ChidiDataError: LocalizedError {
    case invalid(String)
    case unsupportedVersion(Int)
    var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        case .unsupportedVersion(let version): "数据版本 \(version) 暂不支持。请更新 App，原文件未被覆盖。"
        }
    }
}

struct ChidiDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var schemaVersion = currentVersion
    var boards: [TaskBoard] = []
    var tasks: [ChidiTask] = []
    var people: [Person] = []
    var attachments: [AttachmentRecord] = []

    func isDeleted(_ task: ChidiTask) -> Bool {
        task.deletedAt != nil || boards.contains { $0.id == task.boardID && $0.deletedAt != nil }
    }
    func isArchived(_ task: ChidiTask) -> Bool {
        task.archivedAt != nil || boards.contains { $0.id == task.boardID && $0.archivedAt != nil }
    }
    var activeTasks: [ChidiTask] { tasks.filter { !isDeleted($0) && !isArchived($0) } }
    var activeBoards: [TaskBoard] { boards.filter { $0.archivedAt == nil && $0.deletedAt == nil } }

    func searchTasks(_ query: String) -> [ChidiTask] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { task in
            guard !isDeleted(task) else { return false }
            guard !term.isEmpty else { return true }
            let personIDs = Set((task.assignments + task.steps.flatMap(\.assignments)).map(\.personID))
            let names = people.filter { personIDs.contains($0.id) }.flatMap { [$0.name] + $0.tags }
            let board = boards.first { $0.id == task.boardID }?.title ?? ""
            let files = attachments.filter { $0.taskID == task.id && $0.deletedAt == nil }.map(\.filename)
            let fields = [task.title, task.notes, board] + task.steps.flatMap { [$0.title, $0.notes] } + names + files
            return fields.contains { $0.localizedStandardContains(term) }
        }
    }

    func deadlineOccurrences(includeCompleted: Bool = false) -> [DeadlineOccurrence] {
        var result: [DeadlineOccurrence] = []
        for task in activeTasks where includeCompleted || task.status != .completed {
            if let ddl = task.deadline {
                result.append(.init(taskID: task.id, title: task.title, kind: .task, deadline: ddl))
            }
            for assignment in task.assignments {
                if let ddl = assignment.deadline {
                    result.append(.init(taskID: task.id, personID: assignment.personID, title: task.title, kind: .person, deadline: ddl))
                }
            }
            for step in task.steps where includeCompleted || step.status != .completed {
                if let ddl = step.deadline {
                    result.append(.init(taskID: task.id, stepID: step.id, title: step.title, kind: .step, deadline: ddl))
                }
                for assignment in step.assignments {
                    if let ddl = assignment.deadline {
                        result.append(.init(taskID: task.id, stepID: step.id, personID: assignment.personID, title: step.title, kind: .person, deadline: ddl))
                    }
                }
            }
        }
        return result.sorted { $0.deadline.date < $1.deadline.date }
    }

    mutating func upsertTask(_ value: ChidiTask, at now: Date = .now) {
        var task = value
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.updatedAt = now
        let keptSteps = Set(task.steps.map(\.id))
        for index in attachments.indices where attachments[index].taskID == task.id {
            if let stepID = attachments[index].stepID, !keptSteps.contains(stepID) {
                attachments[index].stepID = nil
                attachments[index].deletedAt = attachments[index].deletedAt ?? now
            }
        }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task }
        else { tasks.append(task) }
        if let index = boards.firstIndex(where: { $0.id == task.boardID }) { boards[index].updatedAt = now }
    }

    mutating func restoreTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].deletedAt = nil
        // Restore an individual task from a deleted board into the unclassified list.
        if boards.contains(where: { $0.id == tasks[index].boardID && $0.deletedAt != nil }) {
            tasks[index].boardID = nil
        }
    }

    /// Called at load and before writes; returns file paths eligible for cleanup after commit.
    mutating func purgeExpired(at now: Date = .now, calendar: Calendar = .current) -> [String] {
        let cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86400)
        let boardIDs = Set(boards.filter { ($0.deletedAt ?? .distantFuture) <= cutoff }.map(\.id))
        tasks.removeAll { ($0.deletedAt ?? .distantFuture) <= cutoff || $0.boardID.map(boardIDs.contains) == true }
        boards.removeAll { boardIDs.contains($0.id) }
        let taskIDs = Set(tasks.map(\.id))
        let stepIDs = Set(tasks.flatMap(\.steps).map(\.id))
        let orphaned = attachments.filter { ($0.deletedAt ?? .distantFuture) <= cutoff || !taskIDs.contains($0.taskID) || $0.stepID.map { !stepIDs.contains($0) } == true }
        let removedIDs = Set(orphaned.map(\.id))
        attachments.removeAll { removedIDs.contains($0.id) }
        return orphaned.map(\.relativePath)
    }

    func validate() throws {
        guard schemaVersion == Self.currentVersion else { throw ChidiDataError.unsupportedVersion(schemaVersion) }
        var identities = Set<UUID>()
        func unique(_ id: UUID) throws {
            guard identities.insert(id).inserted else { throw ChidiDataError.invalid("数据中出现重复标识，未保存修改。") }
        }
        func title(_ text: String) throws {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChidiDataError.invalid("名称不能为空。") }
        }
        func deadline(_ value: Deadline?) throws {
            guard let value else { return }
            try unique(value.id)
            guard value.date.timeIntervalSince1970.isFinite else { throw ChidiDataError.invalid("截止时间无效。") }
            for reminder in value.reminders {
                try unique(reminder.id)
                guard reminder.amount >= 0 && reminder.amount <= 100000 else { throw ChidiDataError.invalid("提醒提前量无效。") }
            }
        }
        let personIDs = Set(people.map(\.id))
        let boardIDs = Set(boards.map(\.id))
        func assignments(_ values: [Assignment]) throws {
            var seen = Set<UUID>()
            for value in values {
                try unique(value.id)
                guard personIDs.contains(value.personID), seen.insert(value.personID).inserted else {
                    throw ChidiDataError.invalid("负责人不存在或重复。")
                }
                try deadline(value.deadline)
            }
        }
        for person in people { try unique(person.id); try title(person.name) }
        for board in boards { try unique(board.id); try title(board.title) }
        var retainedTaskTitles = Set<String>()
        for task in tasks {
            try unique(task.id); try title(task.title)
            if !isDeleted(task) {
                let normalized = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_Hans_CN"))
                guard retainedTaskTitles.insert(normalized).inserted else {
                    throw ChidiDataError.invalid("任务名称已存在，请修改名称后再保存。")
                }
            }
            if let id = task.boardID, !boardIDs.contains(id) { throw ChidiDataError.invalid("任务栏不存在。") }
            try deadline(task.deadline); try assignments(task.assignments)
            let stepIDs = Set(task.steps.map(\.id))
            for step in task.steps {
                try unique(step.id); try title(step.title)
                try deadline(step.deadline); try assignments(step.assignments)
                guard !step.predecessorIDs.contains(step.id), Set(step.predecessorIDs).isSubset(of: stepIDs), Set(step.predecessorIDs).count == step.predecessorIDs.count else {
                    throw ChidiDataError.invalid("步骤的前置关系无效。")
                }
            }
            // Reject cycles, but never use dependency state to block starting a step.
            var visiting = Set<UUID>(), visited = Set<UUID>()
            let edges = Dictionary(uniqueKeysWithValues: task.steps.map { ($0.id, $0.predecessorIDs) })
            func visit(_ id: UUID) throws {
                if visiting.contains(id) { throw ChidiDataError.invalid("前置步骤不能形成循环。") }
                if visited.contains(id) { return }
                visiting.insert(id)
                for prior in edges[id] ?? [] { try visit(prior) }
                visiting.remove(id); visited.insert(id)
            }
            for id in stepIDs { try visit(id) }
        }
        for file in attachments {
            try unique(file.id)
            guard let task = tasks.first(where: { $0.id == file.taskID }), file.stepID == nil || task.steps.contains(where: { $0.id == file.stepID }) else {
                throw ChidiDataError.invalid("附件所属任务或步骤不存在。")
            }
            guard AttachmentStorage.isSafePath(file.relativePath) else {
                throw ChidiDataError.invalid("附件路径无效。")
            }
        }
    }
}
