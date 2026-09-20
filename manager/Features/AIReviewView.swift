import SwiftUI

enum NameChoice: Hashable {
    case unresolved, skip, create, existing(UUID)
}

struct AIReviewView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let proposal: NaturalLanguageDraft
    let apply: (ChidiTask, [Person], TaskBoard?) -> Void
    @State private var boardChoice: NameChoice = .skip
    @State private var peopleChoices: [String: NameChoice] = [:]
    @State private var errorText: String?
    private var needsChoice: Bool { boardChoice == .unresolved || proposal.peopleNames.contains { peopleChoices[$0, default: .unresolved] == .unresolved } }

    var body: some View {
        NavigationStack {
            Form {
                Section("原始输入") { Text(proposal.source).textSelection(.enabled) }
                previewSection
                boardSection
                peopleSection
                if !proposal.warnings.isEmpty {
                    Section("还需核对") { ForEach(Array(proposal.warnings.enumerated()), id: \.offset) { Text($0.element).foregroundStyle(.secondary) } }
                }
                Section {
                    Text("没有提到的字段保持为空。下一步可修改所有字段，点击“确认添加”后才会写入任务；新建人员和任务栏也会同时保存。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let errorText { Text(errorText).foregroundStyle(.red) }
                    Button("继续核对并修改") { applyProposal() }.disabled(needsChoice)
                }
            }.navigationTitle("AI 解析预览").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回输入") { dismiss() } } }
                .onAppear { initializeChoices() }
        }
    }

    private var previewSection: some View {
        Section("解析预览 · 尚未创建") {
            LabeledContent("任务", value: proposal.task.title)
            if let id = proposal.task.boardID, let name = store.document.boards.first(where: { $0.id == id })?.title { LabeledContent("入口指定任务栏", value: name) }
            LabeledContent("四象限", value: proposal.task.quadrant?.title ?? "未设置")
            LabeledContent("状态", value: proposal.task.status?.title ?? "未设置")
            if let ddl = proposal.task.deadline {
                DeadlineLabel(deadline: ddl, kind: "总任务 DDL")
                ForEach(ddl.reminders) { reminder in
                    Text("提前 \(reminder.amount) \(reminder.unit.title) · \(reminder.kind == .strong ? "强提醒" : "普通提醒")")
                }
            } else { Text("总任务 DDL：未设置") }
            ForEach(proposal.task.steps) { step in
                VStack(alignment: .leading) {
                    Text("步骤：" + step.title)
                    if let status = step.status { Text(status.title).font(.caption) }
                    let people = proposal.stepPeople[step.id] ?? []
                    if !people.isEmpty { Text("负责人：" + people.joined(separator: "、")).font(.caption) }
                    let prior = proposal.task.steps.filter { step.predecessorIDs.contains($0.id) }
                    if !prior.isEmpty { Text("前置步骤：" + prior.map(\.title).joined(separator: "、")).font(.caption) }
                    if let ddl = step.deadline { DeadlineLabel(deadline: ddl, kind: "步骤 DDL") }
                }
            }
        }
    }

    @ViewBuilder private var boardSection: some View {
        if let board = proposal.boardName {
            Section("任务栏 · \(board)") {
                Picker("对应任务栏", selection: $boardChoice) {
                    Text("请选择对应关系").tag(NameChoice.unresolved)
                    Text("不设置任务栏").tag(NameChoice.skip)
                    Text("新建“\(board)”").tag(NameChoice.create)
                    ForEach(Array(store.document.activeBoards.enumerated()), id: \.element.id) { index, item in
                        Text("\(item.title)（第 \(index + 1) 栏）").tag(NameChoice.existing(item.id))
                    }
                }
            }
        }
    }

    @ViewBuilder private var peopleSection: some View {
        if !proposal.peopleNames.isEmpty {
            Section("负责人对应关系") {
                ForEach(proposal.peopleNames, id: \.self) { name in
                    Picker(name, selection: Binding(get: { peopleChoices[name, default: .unresolved] }, set: { peopleChoices[name] = $0 })) {
                        Text("请选择对应关系").tag(NameChoice.unresolved)
                        Text("暂不分配").tag(NameChoice.skip)
                        Text("新建“\(name)”").tag(NameChoice.create)
                        ForEach(Array(store.document.people.enumerated()), id: \.element.id) { index, person in
                            Text(personLabel(person, index: index)).tag(NameChoice.existing(person.id))
                        }
                    }
                }
                ForEach(proposal.peopleNames, id: \.self) { name in
                    if let ddl = proposal.taskPersonalDeadlines[name] { DeadlineLabel(deadline: ddl, kind: "\(name)的个人 DDL") }
                    ForEach(proposal.task.steps) { step in
                        if let ddl = proposal.stepPersonalDeadlines[step.id]?[name] { DeadlineLabel(deadline: ddl, kind: "\(step.title) · \(name)的个人 DDL") }
                    }
                }
                Text("同名人员请核对标签或备注；如仍无法区分，可先到人员页补充信息。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func personLabel(_ person: Person, index: Int) -> String {
        let detail = person.tags.isEmpty ? String(person.notes.prefix(20)) : person.tags.joined(separator: "/")
        return person.name + " · " + (detail.isEmpty ? "人员列表第 \(index + 1) 位" : detail)
    }

    private func initializeChoices() {
        if let name = proposal.boardName {
            let matches = store.document.activeBoards.filter { $0.title == name }
            boardChoice = matches.count == 1 ? .existing(matches[0].id) : .unresolved
        }
        for name in proposal.peopleNames {
            let matches = store.document.people.filter { $0.name == name }
            peopleChoices[name] = matches.count == 1 ? .existing(matches[0].id) : .unresolved
        }
    }
    private func applyProposal() {
        var task = proposal.task
        var newPeople: [Person] = []
        var mapping: [String: UUID] = [:]
        var newBoard: TaskBoard?
        if let name = proposal.boardName {
            switch boardChoice {
            case .create: let board = TaskBoard(title: name); newBoard = board; task.boardID = board.id
            case .existing(let id): task.boardID = id
            case .skip: task.boardID = nil
            default: break
            }
        }
        for name in proposal.peopleNames {
            switch peopleChoices[name, default: .skip] {
            case .create: let person = Person(name: name); newPeople.append(person); mapping[name] = person.id
            case .existing(let id): mapping[name] = id
            default: break
            }
        }
        do {
            task = try proposal.resolvedTask(boardID: task.boardID, people: mapping)
            apply(task, newPeople, newBoard)
            dismiss()
        } catch { errorText = error.localizedDescription }

    }
}

struct SpeechInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech = SpeechInput()
    let useText: (String) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(speech.text.isEmpty ? "点击开始，说出要记下的事情。" : speech.text).frame(minHeight: 100, alignment: .topLeading)
                    Button(speech.listening ? "停止识别" : speech.finishing ? "正在整理文字…" : speech.requesting ? "正在申请权限…" : "开始语音输入", systemImage: speech.listening ? "stop.circle" : "mic") {
                        if speech.listening { speech.finish() } else { Task { await speech.start() } }
                    }.disabled(speech.requesting || speech.finishing)
                } footer: { Text("使用设备上的中文语音识别，每次最多 60 秒。结束后选择“使用文字”，可回到任务卡片继续修改。") }
                if let error = speech.errorMessage { Text(error).foregroundStyle(.secondary) }
            }.navigationTitle("语音输入").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { speech.stop(); dismiss() }.disabled(speech.requesting) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("使用文字") { speech.stop(); useText(speech.text); dismiss() }.disabled(speech.text.isEmpty || speech.requesting || speech.listening || speech.finishing)
                    }
                }
        }.interactiveDismissDisabled(speech.listening || speech.requesting || speech.finishing)
            .onChange(of: scenePhase) { _, phase in if phase == .background { speech.stop() } }
            .onDisappear { speech.stop() }
    }
}
