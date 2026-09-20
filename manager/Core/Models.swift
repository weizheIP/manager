import Foundation

enum WorkStatus: String, Codable, CaseIterable, Sendable {
    case pending, active, waiting, completed
    var title: String {
        switch self {
        case .pending: "待处理"
        case .active: "进行中"
        case .waiting: "等待中"
        case .completed: "已完成"
        }
    }
}

enum Quadrant: String, Codable, CaseIterable, Sendable {
    case importantUrgent, important, urgent, neither
    var title: String {
        switch self {
        case .importantUrgent: "重要紧急"
        case .important: "重要不紧急"
        case .urgent: "不重要但紧急"
        case .neither: "不重要不紧急"
        }
    }
    var principle: String {
        switch self {
        case .importantUrgent: "立马亲自做"
        case .important: "延后亲自做"
        case .urgent: "交给AI做"
        case .neither: "有空再做"
        }
    }
}

struct Reminder: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable { case ordinary, strong }
    enum Unit: String, Codable, CaseIterable {
        case minutes, hours, days, weeks
        var seconds: TimeInterval {
            switch self { case .minutes: 60; case .hours: 3600; case .days: 86400; case .weeks: 604800 }
        }
    }
    var id = UUID()
    var amount: Int
    var unit: Unit
    var kind: Kind = .ordinary
    func fireDate(for deadline: Date) -> Date { deadline.addingTimeInterval(-Double(amount) * unit.seconds) }
}

struct Deadline: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var includesTime = true
    var reminders: [Reminder] = []

    func overdueDescription(at now: Date = .now, calendar: Calendar = .current) -> String? {
        let boundary = includesTime ? date : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        guard now > boundary else { return nil }
        let hours = max(0, Int(now.timeIntervalSince(boundary) / 3600))
        return hours >= 24 ? "已过 DDL \(hours / 24) 天" : hours > 0 ? "已过 DDL \(hours) 小时" : "已过 DDL 不足 1 小时"
    }
}

struct Assignment: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var personID: UUID
    var deadline: Deadline?
}

struct Person: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var tags: [String] = []
    var notes = ""
}

struct TaskBoard: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var archivedAt: Date?
    var deletedAt: Date?
    var updatedAt = Date.now
}

struct TaskStep: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var status: WorkStatus?
    var deadline: Deadline?
    var assignments: [Assignment] = []
    var notes = ""
    var predecessorIDs: [UUID] = []
}

struct ChidiTask: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var boardID: UUID?
    var quadrant: Quadrant?
    var status: WorkStatus?
    var waitingReason = ""
    var deadline: Deadline?
    var assignments: [Assignment] = []
    var steps: [TaskStep] = []
    var notes = ""
    var createdAt = Date.now
    var updatedAt = Date.now
    var archivedAt: Date?
    var deletedAt: Date?

    var allStepsCompleted: Bool { !steps.isEmpty && steps.allSatisfy { $0.status == .completed } }
    var incompleteSteps: [TaskStep] { steps.filter { $0.status != .completed } }
    func unfinishedPredecessors(of step: TaskStep) -> [TaskStep] {
        steps.filter { step.predecessorIDs.contains($0.id) && $0.status != .completed }
    }
    mutating func removeStep(_ id: UUID) {
        steps.removeAll { $0.id == id }
        for index in steps.indices { steps[index].predecessorIDs.removeAll { $0 == id } }
    }
}

struct AttachmentRecord: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable { case image, file, audio }
    var id = UUID()
    var taskID: UUID
    var stepID: UUID?
    var filename: String
    var relativePath: String
    var kind: Kind
    var createdAt = Date.now
    var deletedAt: Date?
}

struct DeadlineOccurrence: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable { case task = "总任务", step = "步骤", person = "个人" }
    var id: UUID { deadline.id }
    var taskID: UUID
    var stepID: UUID?
    var personID: UUID?
    var title: String
    var kind: Kind
    var deadline: Deadline
}
