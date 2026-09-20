import AlarmKit
import Observation
import SwiftUI
import UserNotifications

struct ReminderRoute: Identifiable {
    var id: UUID { taskID }
    var taskID: UUID
    var stepID: UUID?
    var personID: UUID?
}

private struct ChidiAlarmMetadata: AlarmMetadata {
    var taskID: UUID
}

/// Serial reconciliation: a save arriving during an OS call is applied in the next pass.
@MainActor @Observable
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    var statuses: [UUID: String] = [:]
    var ordinaryPermission = "读取中"
    var strongPermission = "读取中"
    var errorMessage: String?
    var route: ReminderRoute?
    private(set) var isSynchronizing = false
    private var pending: ChidiDocument?
    private var latest = ChidiDocument()
    private let center = UNUserNotificationCenter.current()
    private let prefix = "chidi.reminder."
    private let ledgerKey = "chidi.alarms.scheduled.v1"
    private var alarmLedger: [PlannedReminder] = []

    override init() {
        super.init()
        center.delegate = self
        if let data = UserDefaults.standard.data(forKey: ledgerKey), let saved = try? JSONDecoder().decode([PlannedReminder].self, from: data) {
            alarmLedger = saved
        }
    }

    func refresh(_ document: ChidiDocument) {
        latest = document
        pending = document
        guard !isSynchronizing else { return }
        isSynchronizing = true
        Task {
            while let document = pending {
                pending = nil
                await reconcile(document)
            }
            isSynchronizing = false
        }
    }

    func authorizeOrdinary() async {
        do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { errorMessage = "无法申请通知权限：\(error.localizedDescription)" }
        refresh(latest)
    }

    func authorizeStrong() async {
        do { _ = try await AlarmManager.shared.requestAuthorization() }
        catch { errorMessage = "无法申请闹钟权限：\(error.localizedDescription)" }
        refresh(latest)
    }

    private func reconcile(_ document: ChidiDocument) async {
        let plan = document.reminderPlan()
        let now = Date.now
        var result = Dictionary(uniqueKeysWithValues: plan.filter { $0.fireDate <= now }.map { ($0.id, "提醒时间已过") })
        let settings = await center.notificationSettings()
        let notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral
        ordinaryPermission = notificationsAllowed ? "已允许" : settings.authorizationStatus == .notDetermined ? "尚未申请" : "未允许"
        let alarmsAllowed = AlarmManager.shared.authorizationState == .authorized
        strongPermission = alarmsAllowed ? "已允许" : AlarmManager.shared.authorizationState == .notDetermined ? "尚未申请" : "未允许"
        let ordinary = plan.filter { $0.kind == .ordinary && $0.fireDate > now }
        // Bound the queue explicitly; the remainder stays visible as unscheduled.
        let scheduledOrdinary = Array(ordinary.prefix(60))
        let desiredIDs = Set(scheduledOrdinary.map { prefix + $0.id.uuidString })
        let existing = await center.pendingNotificationRequests()
        let obsolete = existing.filter { $0.identifier.hasPrefix(prefix) && (!desiredIDs.contains($0.identifier) || !notificationsAllowed) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        let liveIDs = Set(plan.map { prefix + $0.id.uuidString })
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix(prefix) && !liveIDs.contains($0.request.identifier) }.map { $0.request.identifier })
        for item in ordinary {
            guard notificationsAllowed else { result[item.id] = "未排定：请允许普通通知"; continue }
            guard desiredIDs.contains(prefix + item.id.uuidString) else { result[item.id] = "待排定：已排入最近 60 条，打开 App 时续排"; continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.detail
            content.sound = .default
            var info = ["taskID": item.taskID.uuidString]
            if let stepID = item.stepID { info["stepID"] = stepID.uuidString }
            if let personID = item.personID { info["personID"] = personID.uuidString }
            content.userInfo = info
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            let request = UNNotificationRequest(identifier: prefix + item.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            do { try await center.add(request); result[item.id] = "普通提醒已排定" }
            catch { result[item.id] = "排定失败：\(error.localizedDescription)" }
        }
        // Read back the OS queue; an accepted add alone is not a delivery guarantee.
        let actual = Set(await center.pendingNotificationRequests().map(\.identifier))
        for item in scheduledOrdinary where result[item.id] == "普通提醒已排定" && !actual.contains(prefix + item.id.uuidString) {
            result[item.id] = item.fireDate <= .now ? "提醒时间已到" : "系统未保留此提醒，请重试"
        }
        let strong = plan.filter { $0.kind == .strong }
        do {
            let alarms = try AlarmManager.shared.alarms
            let wanted = Set(strong.map(\.id))
            for alarm in alarms where !wanted.contains(alarm.id) {
                do { try AlarmManager.shared.cancel(id: alarm.id) }
                catch { errorMessage = "旧强提醒取消失败，请重试：\(error.localizedDescription)" }
            }
            alarmLedger.removeAll { !wanted.contains($0.id) }
            for item in strong {
                guard alarmsAllowed else { if item.fireDate > now { result[item.id] = "未排定：请允许强提醒闹钟" }; continue }
                let existingAlarm = alarms.first { $0.id == item.id }
                if item.fireDate <= now {
                    if existingAlarm != nil && !alarmLedger.contains(item) {
                        do { try AlarmManager.shared.cancel(id: item.id) }
                        catch { result[item.id] = "旧闹钟取消失败，请重试" }
                    }
                    if existingAlarm?.state == .alerting && alarmLedger.contains(item) { result[item.id] = "强提醒正在响铃" }
                    continue
                }
                if existingAlarm != nil && alarmLedger.contains(item) { result[item.id] = "强提醒已排定"; continue }
                do {
                    if existingAlarm != nil { try AlarmManager.shared.cancel(id: item.id) }
                    let presentation = AlarmPresentation(alert: .init(title: "\(item.title) · \(item.detail)"))
                    let attributes = AlarmAttributes(presentation: presentation, metadata: ChidiAlarmMetadata(taskID: item.taskID), tintColor: ChidiStyle.purple)
                    let configuration = AlarmManager.AlarmConfiguration.alarm(schedule: .fixed(item.fireDate), attributes: attributes)
                    _ = try await AlarmManager.shared.schedule(id: item.id, configuration: configuration)
                    alarmLedger.removeAll { $0.id == item.id }
                    alarmLedger.append(item)
                    result[item.id] = "强提醒已排定"
                } catch { result[item.id] = "强提醒未排定：\(error.localizedDescription)" }
            }
            if let data = try? JSONEncoder().encode(alarmLedger) { UserDefaults.standard.set(data, forKey: ledgerKey) }
        } catch {
            for item in strong where item.fireDate > now { result[item.id] = "闹钟服务不可用：\(error.localizedDescription)" }
        }
        statuses = result
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let raw = info["taskID"] as? String, let id = UUID(uuidString: raw) {
            let step = (info["stepID"] as? String).flatMap(UUID.init(uuidString:))
            let person = (info["personID"] as? String).flatMap(UUID.init(uuidString:))
            Task { @MainActor in self.route = ReminderRoute(taskID: id, stepID: step, personID: person) }
        }
        completionHandler()
    }
}
