import SwiftUI

extension Reminder.Unit {
    var title: String {
        switch self { case .minutes: "分钟"; case .hours: "小时"; case .days: "天"; case .weeks: "周" }
    }
}

struct ReminderEditor: View {
    @Binding var deadline: Deadline
    var body: some View {
        DisclosureGroup("提醒（\(deadline.reminders.count)）") {
            if !deadline.includesTime {
                Text("仅设日期时，提醒按当日 09:00 计算；DDL 仍是这一天。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach($deadline.reminders) { $reminder in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("提前")
                        TextField("数量", value: $reminder.amount, format: .number.grouping(.never))
                            .keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(minWidth: 48)
                        Picker("单位", selection: $reminder.unit) {
                            ForEach(Reminder.Unit.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden()
                    }
                    Picker("方式", selection: $reminder.kind) {
                        Text("普通提醒").tag(Reminder.Kind.ordinary)
                        Text("强提醒（闹钟）").tag(Reminder.Kind.strong)
                    }
                    Button("移除此提醒", role: .destructive) { deadline.reminders.removeAll { $0.id == reminder.id } }
                        .font(.caption)
                }.padding(.vertical, 6)
            }
            Button("添加提醒", systemImage: "bell.badge") { deadline.reminders.append(Reminder(amount: 0, unit: .minutes)) }
            Text("提前 0 表示到期时提醒。保存后生效，可在“提醒设置”查看权限和排定结果。").font(.caption).foregroundStyle(.secondary)
            NavigationLink("提醒设置") { ReminderSettingsView() }
        }
    }
}

struct ReminderSettingsView: View {
    @Environment(TaskStore.self) private var store
    @Environment(ReminderService.self) private var service
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section("普通提醒") {
                LabeledContent("通知权限", value: service.ordinaryPermission)
                Button("允许普通通知") { Task { await service.authorizeOrdinary() } }
                Text("普通通知的声音和展示受静音、专注模式及系统通知设置影响。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("强提醒") {
                LabeledContent("闹钟权限", value: service.strongPermission)
                Button("允许强提醒闹钟") { Task { await service.authorizeStrong() } }
                Text("强提醒使用 iPhone 的系统闹钟。权限未允许或排定失败时，会明确标记为未排定。").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                Button(service.isSynchronizing ? "正在刷新…" : "刷新提醒") { service.refresh(store.document) }.disabled(service.isSynchronizing)
                if let message = service.errorMessage { Text(message).font(.footnote).foregroundStyle(.red) }
            }
            Section {
                let plan = store.document.reminderPlan()
                if plan.isEmpty { Text("尚未设置提醒。可在任务、步骤或个人 DDL 中添加。").foregroundStyle(.secondary) }
                ForEach(plan) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.headline)
                        Text(item.detail + (item.kind == .strong ? " · 强提醒" : " · 普通提醒"))
                        Text(item.fireDate, format: .dateTime.year().month().day().hour().minute())
                        Text(service.statuses[item.id] ?? "等待排定")
                    }.font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("提醒排定结果") } footer: {
                Text("普通提醒每次排入最近 60 条，其余在打开 App 或保存修改时续排。未排定的提醒不会响铃，请留意列表。已完成、归档或删除的事项会撤销提醒。")
            }
        }.navigationTitle("提醒设置").navigationBarTitleDisplayMode(.inline)
            .onAppear { service.refresh(store.document) }
    }
}
