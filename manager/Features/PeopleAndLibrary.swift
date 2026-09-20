import SwiftUI

struct PeoplePage: View {
    @Environment(TaskStore.self) private var store
    @State private var adding = false
    var body: some View {
        List {
            if store.document.people.isEmpty { ContentUnavailableView("还没有人员", systemImage: "person.2", description: Text("添加姓名，再为任务和步骤分配负责人。")) }
            ForEach(store.document.people) { person in
                NavigationLink { PersonDetailView(personID: person.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(person.name).font(.headline)
                        if !person.tags.isEmpty { Text(person.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        let tasks = store.document.activeTasks.filter { $0.assignments.contains { $0.personID == person.id } || $0.steps.contains { $0.assignments.contains { $0.personID == person.id } } }
                        Text("\(tasks.filter { $0.status != .completed }.count) 项未完成事务").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .toolbar { Button("添加人员", systemImage: "person.badge.plus") { adding = true } }
        .sheet(isPresented: $adding) { PersonEditor() }
    }
}

struct PersonEditor: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var person: Person?
    @State private var name = ""
    @State private var tags = ""
    @State private var notes = ""
    @State private var errorText: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("姓名（必填）", text: $name)
                TextField("标签，用逗号分隔", text: $tags)
                TextField("备注", text: $notes, axis: .vertical).lineLimit(3...8)
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }.navigationTitle(person == nil ? "添加人员" : "编辑人员").navigationBarTitleDisplayMode(.inline)
                .onAppear { name = person?.name ?? ""; tags = person?.tags.joined(separator: "，") ?? ""; notes = person?.notes ?? "" }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            var value = person ?? Person(name: "")
                            value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            value.tags = Array(Set(tags.components(separatedBy: CharacterSet(charactersIn: ",，")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
                            value.notes = notes
                            if store.change({ doc in
                                if let index = doc.people.firstIndex(where: { $0.id == value.id }) { doc.people[index] = value }
                                else { doc.people.append(value) }
                            }) { dismiss() } else { errorText = store.errorMessage; store.errorMessage = nil }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}

struct PersonDetailView: View {
    @Environment(TaskStore.self) private var store
    let personID: UUID
    @State private var editing = false
    private var assignedTasks: [ChidiTask] { store.document.activeTasks.filter { $0.assignments.contains { $0.personID == personID } } }
    private var assignedSteps: [(task: ChidiTask, step: TaskStep)] {
        store.document.activeTasks.flatMap { task in task.steps.filter { $0.assignments.contains { $0.personID == personID } }.map { (task, $0) } }
    }
    var body: some View {
        if let person = store.document.people.first(where: { $0.id == personID }) {
            List {
                Section("负载") {
                    let statuses = assignedTasks.map(\.status) + assignedSteps.map { $0.step.status }
                    LabeledContent("未完成", value: "\(statuses.filter { $0 != .completed }.count)")
                    LabeledContent("进行中", value: "\(statuses.filter { $0 == .active }.count)")
                    LabeledContent("等待中", value: "\(statuses.filter { $0 == .waiting }.count)")
                    if !person.tags.isEmpty { Text(person.tags.joined(separator: " · ")) }
                    if !person.notes.isEmpty { Text(person.notes) }
                }
                Section("四象限分布 · 未完成任务") {
                    ForEach(Quadrant.allCases, id: \.self) { quadrant in
                        LabeledContent(quadrant.title, value: "\(assignedTasks.filter { $0.quadrant == quadrant && $0.status != .completed }.count)")
                    }
                }
                Section("近期个人 DDL") {
                    let deadlines = store.document.deadlineOccurrences().filter { $0.personID == personID }
                    if deadlines.isEmpty { Text("暂无个人 DDL").foregroundStyle(.secondary) }
                    ForEach(deadlines) { DeadlineLink(occurrence: $0) }
                }
                Section("负责的任务") {
                    ForEach(assignedTasks) { task in NavigationLink { TaskDetailView(taskID: task.id, initialPersonID: personID) } label: { TaskRow(task: task) } }
                }
                Section("负责的步骤") {
                    ForEach(assignedSteps, id: \.step.id) { item in
                        NavigationLink {
                            TaskDetailView(taskID: item.task.id, initialStepID: item.step.id, initialPersonID: personID)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.step.title)
                                Text("\(item.task.title) · \(item.step.status?.title ?? "未设置状态")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.navigationTitle(person.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("编辑") { editing = true } }
                .sheet(isPresented: $editing) { PersonEditor(person: person) }
        }
    }
}

struct SearchPage: View {
    @Environment(TaskStore.self) private var store
    @State private var query = ""
    var body: some View {
        List {
            Section("任务栏") {
                ForEach(store.document.boards.filter { $0.deletedAt == nil && (query.isEmpty || $0.title.localizedStandardContains(query)) }) { board in
                    if board.archivedAt == nil { NavigationLink(board.title) { BoardDetailView(boardID: board.id) } }
                    else { Text("\(board.title) · 已归档（可在归档页恢复）") }
                }
            }
            Section("人员") {
                ForEach(store.document.people.filter { query.isEmpty || ([$0.name, $0.notes] + $0.tags).contains { $0.localizedStandardContains(query) } }) { person in
                    NavigationLink(person.name) { PersonDetailView(personID: person.id) }
                }
            }
            Section("任务与步骤 · 包括归档") {
                ForEach(store.document.searchTasks(query)) { task in NavigationLink { TaskDetailView(taskID: task.id) } label: { TaskRow(task: task) } }
            }
        }.navigationTitle("全局搜索").searchable(text: $query, prompt: "任务、步骤、人员、标签、备注或文件名")
    }
}

struct LibraryPage: View {
    @Environment(TaskStore.self) private var store
    let isTrash: Bool
    var body: some View {
        List {
            Section {
                Text(isTrash ? "删除的内容保留 30 天，到期后会在打开 App 或保存时清理。" : "归档内容不出现在日常视图中，仍然可以搜索和恢复。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("任务栏") {
                ForEach(store.document.boards.filter { isTrash ? $0.deletedAt != nil : $0.archivedAt != nil && $0.deletedAt == nil }) { board in
                    HStack {
                        Text(board.title)
                        Spacer()
                        Button("恢复") { store.change { doc in
                            if let i = doc.boards.firstIndex(where: { $0.id == board.id }) {
                                if isTrash { doc.boards[i].deletedAt = nil } else { doc.boards[i].archivedAt = nil }
                            }
                        } }.buttonStyle(.bordered)
                    }
                }
            }
            Section("任务") {
                ForEach(store.document.tasks.filter { isTrash ? store.document.isDeleted($0) : store.document.isArchived($0) && !store.document.isDeleted($0) }) { task in
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink { TaskDetailView(taskID: task.id) } label: { TaskRow(task: task) }
                        Button("恢复任务") {
                            store.change { doc in
                                if isTrash { doc.restoreTask(task.id) }
                                else if let i = doc.tasks.firstIndex(where: { $0.id == task.id }) {
                                    doc.tasks[i].archivedAt = nil
                                    if doc.boards.contains(where: { $0.id == doc.tasks[i].boardID && $0.archivedAt != nil }) { doc.tasks[i].boardID = nil }
                                }
                            }
                        }.buttonStyle(.bordered)
                    }
                }
            }
            if isTrash {
                Section("已移除的附件") {
                    ForEach(store.document.attachments.filter { $0.deletedAt != nil }) { file in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(file.filename)
                            let owner = store.task(file.taskID)
                            Text(owner?.title ?? "任务不存在").font(.caption).foregroundStyle(.secondary)
                            if let owner, !store.document.isDeleted(owner) {
                                Button("恢复附件") {
                                    store.change { doc in
                                        if let index = doc.attachments.firstIndex(where: { $0.id == file.id }) { doc.attachments[index].deletedAt = nil }
                                    }
                                }.buttonStyle(.bordered)
                            } else { Text("请先恢复所属任务，再恢复附件。").font(.caption) }
                        }
                    }
                }
            }
        }.navigationTitle(isTrash ? "废纸篓" : "归档").navigationBarTitleDisplayMode(.inline)
    }
}
