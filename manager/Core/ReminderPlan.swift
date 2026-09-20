import Foundation

struct PlannedReminder: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var taskID: UUID
    var stepID: UUID?
    var personID: UUID?
    var title: String
    var detail: String
    var fireDate: Date
    var kind: Reminder.Kind
}

extension ChidiDocument {
    /// Date-only deadlines use 09:00 local time as a visible, consistent reminder anchor.
    func reminderPlan(calendar: Calendar = .current) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        for occurrence in deadlineOccurrences() {
            let deadline = occurrence.deadline
            let anchor = deadline.includesTime ? deadline.date : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: deadline.date) ?? deadline.date
            let person = people.first { $0.id == occurrence.personID }?.name
            let detail = occurrence.kind.rawValue + " DDL" + (person.map { " · " + $0 } ?? "")
            for reminder in deadline.reminders {
                let planned = PlannedReminder(id: reminder.id, taskID: occurrence.taskID, stepID: occurrence.stepID,
                                personID: occurrence.personID, title: occurrence.title,
                                detail: detail,
                                fireDate: reminder.fireDate(for: anchor), kind: reminder.kind)
                result.append(planned)
            }
        }
        return result.sorted { $0.fireDate == $1.fireDate ? $0.id.uuidString < $1.id.uuidString : $0.fireDate < $1.fireDate }
    }
}
