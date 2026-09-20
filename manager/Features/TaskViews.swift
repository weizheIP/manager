import SwiftUI

struct TaskRow: View {
    @Environment(TaskStore.self) private var store
    let task: ChidiTask
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(task.title).font(.headline).foregroundStyle(.primary)
            HStack {
                if let status = task.status { Text(status.title) }
                if let quadrant = task.quadrant { Text(quadrant.title) }
                if store.document.isArchived(task) { Text("已归档") }
            }.font(.caption).foregroundStyle(.secondary)
            if let deadline = task.deadline { DeadlineLabel(deadline: deadline, kind: "总任务 DDL") }
        }.padding(.vertical, 5)
    }
}

struct DeadlineLabel: View {
    @Environment(ReminderService.self) private var service
    let deadline: Deadline
    let kind: String
    var showReminders = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(kind) · \(deadline.date.formatted(date: .abbreviated, time: deadline.includesTime ? .shortened : .omitted))")
            if let overdue = deadline.overdueDescription() { Text(overdue) }
            if showReminders {
                ForEach(deadline.reminders) { reminder in
                    Text("提前 \(reminder.amount) \(reminder.unit.title) · \(reminder.kind == .strong ? "强提醒" : "普通提醒")")
                    Text(service.statuses[reminder.id] ?? (service.isSynchronizing ? "等待排定" : "当前事项未启用提醒"))
                }
                if !deadline.reminders.isEmpty { NavigationLink("查看提醒设置") { ReminderSettingsView() } }
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct DeadlineEditor: View {
    @Binding var deadline: Deadline?
    var title = "DDL"
    var body: some View {
        Toggle("设置\(title)", isOn: Binding(get: { deadline != nil }, set: { deadline = $0 ? Deadline(date: .now) : nil }))
        if deadline != nil {
            Toggle("包含具体时间", isOn: Binding(get: { deadline?.includesTime ?? true }, set: { deadline?.includesTime = $0 }))
            DatePicker(title, selection: Binding(get: { deadline?.date ?? .now }, set: { deadline?.date = $0 }), displayedComponents: deadline?.includesTime == true ? [.date, .hourAndMinute] : [.date])
            if let value = deadline {
                ReminderEditor(deadline: Binding(get: { deadline ?? value }, set: { deadline = $0 }))
            }
        }
    }
}

struct AssignmentEditor: View {
    @Environment(TaskStore.self) private var store
    @Binding var assignments: [Assignment]
    var additionalPeople: [Person] = []
    var body: some View {
        if store.document.people.isEmpty && additionalPeople.isEmpty {
            Text("可先在人员页添加负责人；也可以暂时不分配。").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(store.document.people + additionalPeople) { person in
            Toggle(person.name, isOn: Binding(
                get: { assignments.contains { $0.personID == person.id } },
                set: { selected in
                    if selected { assignments.append(Assignment(personID: person.id)) }
                    else { assignments.removeAll { $0.personID == person.id } }
                }
            ))
            if let index = assignments.firstIndex(where: { $0.personID == person.id }) {
                DeadlineEditor(deadline: $assignments[index].deadline, title: "\(person.name)的个人 DDL")
            }
        }
    }
}

struct TaskEditor: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ChidiTask
    private let original: ChidiTask
    let isNew: Bool
    private let startParsing: Bool
    @State private var didStartParsing = false
    @State private var discard = false
    @State private var confirmCompletion = false
    @State private var confirmIncomplete = false
    @State private var errorText: String?
    @State private var proposal: NaturalLanguageDraft?
    @State private var pendingPeople: [Person] = []
    @State private var pendingBoard: TaskBoard?
    @State private var aiSource: String?
    @State private var showMore = false
    @State private var showSpeech = false
    @State private var parsing = false
    @State private var parseID = UUID()
    @State private var parseTask: Task<Void, Never>?

    init(task: ChidiTask = ChidiTask(title: ""), isNew: Bool = false, startParsing: Bool = false) {
        original = task
        _draft = State(initialValue: task)
        self.isNew = isNew
        self.startParsing = startParsing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任务名称（唯一必填）", text: $draft.title, axis: .vertical)
                        .accessibilityIdentifier("quickAdd.name").disabled(parsing)
                } footer: { Text("先记下名称，其余信息可以稍后补充。") }
                if isNew {
                    Section {
                        HStack {
                            Button("语音输入", systemImage: "mic") { showSpeech = true }.disabled(parsing)
                            Spacer()
                            Button(parsing ? "取消解析" : "AI 解析", systemImage: "sparkles") {
                                if parsing { cancelParsing() } else { parse() }
                            }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.buttonStyle(.borderless)
                        if parsing { ProgressView("正在提取你明确说出的内容…") }
                        if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }
                        if let aiSource {
                            Text("待确认 · 原始输入：\(aiSource)").font(.caption).foregroundStyle(.secondary)
                        } else { Text("AI 使用本地模型；只输入名称也可直接保存。").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    DisclosureGroup("更多设置", isExpanded: $showMore) {
                        Picker("任务栏", selection: $draft.boardID) {
                            Text("未分类").tag(Optional<UUID>.none)
                            ForEach(store.document.boards.filter { $0.deletedAt == nil } + (pendingBoard.map { [$0] } ?? [])) { Text($0.title).tag(Optional($0.id)) }
                        }
                        Picker("四象限", selection: $draft.quadrant) {
                            Text("未分类").tag(Optional<Quadrant>.none)
                            ForEach(Quadrant.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }
                        Picker("状态", selection: $draft.status) {
                            Text("未设置").tag(Optional<WorkStatus>.none)
                            ForEach(WorkStatus.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }
                        if draft.status == .waiting { TextField("等待原因", text: $draft.waitingReason, axis: .vertical) }
                        DeadlineEditor(deadline: $draft.deadline, title: "总任务 DDL")
                    }
                }
                Section("负责人") { DisclosureGroup("分配负责人和个人 DDL") { AssignmentEditor(assignments: $draft.assignments, additionalPeople: pendingPeople) } }
                Section("步骤") {
                    ForEach($draft.steps) { $step in
                        DisclosureGroup(step.title.isEmpty ? "新步骤" : step.title) {
                            TextField("步骤名称", text: $step.title)
                            Picker("状态", selection: $step.status) {
                                Text("未设置").tag(Optional<WorkStatus>.none)
                                ForEach(WorkStatus.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                            }
                            if !draft.unfinishedPredecessors(of: step).isEmpty {
                                Label("有前置步骤尚未完成，仍可继续。", systemImage: "exclamationmark.triangle").font(.caption)
                            }
                            DeadlineEditor(deadline: $step.deadline, title: "步骤 DDL")
                            DisclosureGroup("步骤负责人") { AssignmentEditor(assignments: $step.assignments, additionalPeople: pendingPeople) }
                            DisclosureGroup("前置步骤（不选即为并行）") {
                                ForEach(draft.steps.filter { $0.id != step.id }) { previous in
                                    Toggle(previous.title, isOn: Binding(
                                        get: { step.predecessorIDs.contains(previous.id) },
                                        set: { chosen in
                                            if chosen { step.predecessorIDs.append(previous.id) }
                                            else { step.predecessorIDs.removeAll { $0 == previous.id } }
                                        }
                                    ))
                                }
                            }
                            TextField("步骤备注", text: $step.notes, axis: .vertical).lineLimit(2...6)
                        }
                    }
                    .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { indices in
                        let ids = indices.map { draft.steps[$0].id }
                        ids.forEach { draft.removeStep($0) }
                    }
                    Button("添加步骤", systemImage: "plus") { draft.steps.append(TaskStep(title: "")) }
                }
                Section("备注") {
                    TextField("补充说明", text: $draft.notes, axis: .vertical).lineLimit(3...10)
                    Text("保存任务后，可在任务详情或展开的步骤中添加图片、文件和录音。").font(.caption).foregroundStyle(.secondary)
                }
                if !isNew, let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            }
            .navigationTitle(isNew ? "记下一件事" : "编辑任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if draft != original { discard = true } else { dismiss() } }
                        .accessibilityIdentifier("quickAdd.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(aiSource == nil ? "保存" : "确认添加") {
                        if draft.status == .completed && original.status != .completed { confirmCompletion = true }
                        else { save() }
                    }
                    .disabled(parsing || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("task.save")
                }
                ToolbarItem(placement: .bottomBar) { EditButton() }
            }
            .confirmationDialog("放弃尚未保存的修改？", isPresented: $discard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
            }
            .alert("确认完成任务？", isPresented: $confirmCompletion) {
                Button("取消", role: .cancel) {}
                Button("完成") { if draft.incompleteSteps.isEmpty { save() } else { confirmIncomplete = true } }
            } message: { Text("完成只改变状态，不会自动归档。") }
            .alert("仍有 \(draft.incompleteSteps.count) 个步骤未完成", isPresented: $confirmIncomplete) {
                Button("返回检查", role: .cancel) {}
                Button("仍然完成") { save() }
            } message: { Text("这些步骤不会自动变为完成，是否继续？") }
        }
        .sheet(isPresented: $showSpeech) {
            SpeechInputSheet { text in draft.title = text }
        }
        .sheet(item: $proposal) { value in
            AIReviewView(proposal: value) { task, people, board in
                draft = task; pendingPeople = people; pendingBoard = board
                aiSource = value.source; showMore = true
            }
        }
        .task { if startParsing && !didStartParsing { didStartParsing = true; parse() } }
        .onDisappear { cancelParsing() }
        .interactiveDismissDisabled(draft != original || parsing)
        .tint(ChidiStyle.purple)
    }

    private func cancelParsing() { parseID = UUID(); parseTask?.cancel(); parseTask = nil; parsing = false }
    private func parse() {
        cancelParsing()
        let source = draft.title
        let id = UUID(); parseID = id; parsing = true; errorText = nil
        parseTask = Task {
            do {
                var result = try await LocalTaskParser.parse(source)
                result.task.boardID = original.boardID
                guard parseID == id, !Task.isCancelled else { return }
                proposal = result
            } catch is CancellationError {} catch { if parseID == id { errorText = error.localizedDescription } }
            if parseID == id { parsing = false; parseTask = nil }
        }
    }

    private func save() {
        if store.saveTask(draft, adding: pendingPeople, board: pendingBoard) { dismiss() }
        else { errorText = store.errorMessage; store.errorMessage = nil }
    }
}

struct TaskDetailView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    var initialStepID: UUID?
    var initialPersonID: UUID?
    @State private var editing = false
    @State private var expanded = Set<UUID>()
    @State private var complete = false
    @State private var completeWithSteps = false

    var body: some View {
        if let task = store.task(taskID) {
            ScrollViewReader { proxy in
                List {
                    Section("摘要") {
                        Text(task.title).font(.title2)
                        LabeledContent("任务栏", value: store.document.boards.first { $0.id == task.boardID }?.title ?? "未分类")
                        LabeledContent("四象限", value: task.quadrant.map { "\($0.title) · \($0.principle)" } ?? "未分类")
                        LabeledContent("状态", value: task.status?.title ?? "未设置")
                        if task.status == .waiting && !task.waitingReason.isEmpty { Text(task.waitingReason) }
                        if let ddl = task.deadline { DeadlineLabel(deadline: ddl, kind: "总任务 DDL", showReminders: true) }
                    }
                    Section("负责人") {
                        if task.assignments.isEmpty { Text("暂未分配").foregroundStyle(.secondary) }
                        assignmentRows(task.assignments)
                    }
                    Section("步骤") {
                        if task.steps.isEmpty { Text("暂无步骤").foregroundStyle(.secondary) }
                        ForEach(Array(task.steps.enumerated()), id: \.element.id) { index, step in
                            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(step.id) }, set: { if $0 { expanded.insert(step.id) } else { expanded.remove(step.id) } })) {
                                Text(step.status?.title ?? "未设置状态").font(.subheadline)
                                if let ddl = step.deadline { DeadlineLabel(deadline: ddl, kind: "步骤 DDL", showReminders: true) }
                                assignmentRows(step.assignments)
                                let unfinished = task.unfinishedPredecessors(of: step)
                                if !unfinished.isEmpty {
                                    Label("前置未完成：" + unfinished.map(\.title).joined(separator: "、") + "。仍可继续执行。", systemImage: "exclamationmark.triangle").font(.caption)
                                }
                                if !step.notes.isEmpty { Text(step.notes) }
                                AttachmentRows(taskID: task.id, stepID: step.id)
                            } label: {
                                Text("\(index + 1). \(step.title)")
                            }.id(step.id)
                        }
                        if task.allStepsCompleted && task.status != .completed {
                            Text("所有步骤已完成，你可以在下方确认完成总任务。").foregroundStyle(ChidiStyle.purple)
                        }
                    }
                    Section("备注与附件") {
                        Text(task.notes.isEmpty ? "暂无文字备注" : task.notes).textSelection(.enabled)
                        AttachmentRows(taskID: task.id)
                    }
                    if !store.document.isDeleted(task) {
                        Section {
                            Button(task.status == .completed ? "重新打开任务" : "完成任务") {
                                if task.status == .completed { var copy = task; copy.status = .pending; store.saveTask(copy) }
                                else { complete = true }
                            }
                            Button(store.document.isArchived(task) ? "取消归档" : "归档任务") {
                                var copy = task
                                if store.document.isArchived(task) {
                                    copy.archivedAt = nil
                                    if store.document.boards.contains(where: { $0.id == task.boardID && $0.archivedAt != nil }) { copy.boardID = nil }
                                } else { copy.archivedAt = .now }
                                if store.saveTask(copy) { dismiss() }
                            }
                            Button("移到废纸篓", role: .destructive) {
                                var copy = task; copy.deletedAt = .now
                                if store.saveTask(copy) { dismiss() }
                            }
                        }
                    }
                }
                .onAppear {
                    if let initialStepID { expanded.insert(initialStepID) }
                    let assignments = initialStepID.flatMap { id in task.steps.first { $0.id == id }?.assignments } ?? task.assignments
                    let assignmentID = assignments.first { $0.personID == initialPersonID }?.id
                    if let target = assignmentID ?? initialStepID {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("任务详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("编辑") { editing = true } }
            .sheet(isPresented: $editing) { TaskEditor(task: task) }
            .alert("确认完成任务？", isPresented: $complete) {
                Button("取消", role: .cancel) {}
                Button("完成") { if task.incompleteSteps.isEmpty { finish(task) } else { completeWithSteps = true } }
            } message: { Text("完成只改变状态，不会自动归档。") }
            .alert("还有 \(task.incompleteSteps.count) 个步骤未完成", isPresented: $completeWithSteps) {
                Button("返回检查", role: .cancel) {}
                Button("仍然完成") { finish(task) }
            } message: { Text("确认后总任务会完成，步骤状态保持不变。") }
        } else { ContentUnavailableView("任务不存在", systemImage: "tray") }
    }

    @ViewBuilder private func assignmentRows(_ values: [Assignment]) -> some View {
        ForEach(values) { assignment in
            VStack(alignment: .leading, spacing: 5) {
                Text(store.document.people.first { $0.id == assignment.personID }?.name ?? "未知人员")
                if let ddl = assignment.deadline { DeadlineLabel(deadline: ddl, kind: "个人 DDL", showReminders: true) }
            }.id(assignment.id)
        }
    }
    private func finish(_ task: ChidiTask) { var copy = task; copy.status = .completed; store.saveTask(copy) }
}
