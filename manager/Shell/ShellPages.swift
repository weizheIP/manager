import SwiftUI

struct OverviewPage: View {
    @Environment(TaskStore.self) private var store
    private var today: [DeadlineOccurrence] { store.document.deadlineOccurrences().filter { Calendar.current.isDateInToday($0.deadline.date) } }
    private var upcoming: [DeadlineOccurrence] {
        let cal = Calendar.current, start = Calendar.current.startOfDay(for: .now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: start)!
        let end = cal.date(byAdding: .day, value: 8, to: start)!
        return store.document.deadlineOccurrences().filter { $0.deadline.date >= tomorrow && $0.deadline.date < end }
    }
    var body: some View {
        List {
            Section {
                DailyReadingCard()
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section("今日重点") {
                if today.isEmpty { Text("今天暂无到期事项").foregroundStyle(.secondary) }
                ForEach(today) { DeadlineLink(occurrence: $0) }
            }
            Section("四象限") {
                ForEach(Quadrant.allCases, id: \.self) { quadrant in
                    NavigationLink {
                        TaskListView(filter: .quadrant(quadrant), title: quadrant.title)
                    } label: {
                        HStack {
                            Circle().fill(quadrant.color).frame(width: 8, height: 8).accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(quadrant.title)
                                Text(quadrant.principle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(store.document.activeTasks.filter { $0.quadrant == quadrant && $0.status != .completed }.count)").foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink("未分类任务") { TaskListView(filter: .noQuadrant, title: "未分类四象限") }
            }
            Section("即将到期 · 明天起 7 天") {
                if upcoming.isEmpty { Text("未来 7 天暂无到期事项").foregroundStyle(.secondary) }
                ForEach(upcoming) { DeadlineLink(occurrence: $0) }
            }
            Section("最近任务栏") {
                if store.document.activeBoards.isEmpty { Text("在任务栏页建立第一栏").foregroundStyle(.secondary) }
                ForEach(store.document.activeBoards.sorted { $0.updatedAt > $1.updatedAt }.prefix(5)) { board in
                    NavigationLink(board.title) { BoardDetailView(boardID: board.id) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { NavigationLink { SearchPage() } label: { Image(systemName: "magnifyingglass").accessibilityLabel("全局搜索") } }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("更多", systemImage: "ellipsis.circle") {
                    NavigationLink("提醒设置") { ReminderSettingsView() }
                    NavigationLink("归档") { LibraryPage(isTrash: false) }
                    NavigationLink("废纸篓") { LibraryPage(isTrash: true) }
                }
            }
        }
    }
}

extension Quadrant {
    var color: Color {
        switch self {
        case .importantUrgent: Color(red: 0.70, green: 0.42, blue: 0.43)
        case .important: Color(red: 0.65, green: 0.53, blue: 0.27)
        case .urgent: Color(red: 0.40, green: 0.54, blue: 0.66)
        case .neither: .gray
        }
    }
}

enum TaskFilter {
    case all, unclassified, board(UUID), quadrant(Quadrant), noQuadrant
    func matches(_ task: ChidiTask) -> Bool {
        switch self {
        case .all: true
        case .unclassified: task.boardID == nil
        case .board(let id): task.boardID == id
        case .quadrant(let value): task.quadrant == value
        case .noQuadrant: task.quadrant == nil
        }
    }
}

struct TaskListView: View {
    @Environment(TaskStore.self) private var store
    let filter: TaskFilter
    let title: String
    @State private var adding = false
    private var tasks: [ChidiTask] { store.document.activeTasks.filter { filter.matches($0) } }
    var body: some View {
        List {
            if tasks.isEmpty { ContentUnavailableView("暂无任务", systemImage: "checklist", description: Text("点右上角添加，只写名称即可保存。")) }
            ForEach(tasks) { task in NavigationLink { TaskDetailView(taskID: task.id) } label: { TaskRow(task: task) } }
                .onDelete { indices in
                    let ids = indices.map { tasks[$0].id }
                    store.change { doc in for i in doc.tasks.indices where ids.contains(doc.tasks[i].id) { doc.tasks[i].deletedAt = .now } }
                }
                .onMove { source, destination in
                    var ordered = tasks; ordered.move(fromOffsets: source, toOffset: destination)
                    let ids = Set(ordered.map(\.id))
                    store.change { doc in
                        var offset = 0
                        for i in doc.tasks.indices where ids.contains(doc.tasks[i].id) { doc.tasks[i] = ordered[offset]; offset += 1 }
                    }
                }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) { Button("添加", systemImage: "plus") { adding = true } }
        }
        .sheet(isPresented: $adding) {
            if case .board(let id) = filter { TaskEditor(task: ChidiTask(title: "", boardID: id), isNew: true) }
            else { TaskEditor(isNew: true) }
        }
    }
}

struct BoardsPage: View {
    @Environment(TaskStore.self) private var store
    @State private var adding = false
    var body: some View {
        List {
            Section {
                NavigationLink { TaskListView(filter: .all, title: "全部任务") } label: { Label("全部任务", systemImage: "tray.full") }
                NavigationLink { TaskListView(filter: .unclassified, title: "未分类") } label: { Label("未分类", systemImage: "tray") }
            }
            Section("我的任务栏") {
                if store.document.activeBoards.isEmpty { Text("按项目、生活或目标建立任务栏。").foregroundStyle(.secondary) }
                ForEach(store.document.activeBoards) { board in
                    NavigationLink { BoardDetailView(boardID: board.id) } label: {
                        HStack { Text(board.title); Spacer(); Text("\(store.document.activeTasks.filter { $0.boardID == board.id }.count)").foregroundStyle(.secondary) }
                    }
                }
                .onMove { source, destination in
                    var ordered = store.document.activeBoards; ordered.move(fromOffsets: source, toOffset: destination)
                    let ids = Set(ordered.map(\.id))
                    store.change { doc in doc.boards = ordered + doc.boards.filter { !ids.contains($0.id) } }
                }
            }
            Section {
                NavigationLink("提醒设置") { ReminderSettingsView() }
                NavigationLink("归档") { LibraryPage(isTrash: false) }
                NavigationLink("废纸篓") { LibraryPage(isTrash: true) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) { Button("新建任务栏", systemImage: "folder.badge.plus") { adding = true } }
        }
        .sheet(isPresented: $adding) { BoardEditor() }
    }
}

struct BoardEditor: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var board: TaskBoard?
    @State private var name = ""
    @State private var errorText: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("任务栏名称", text: $name).accessibilityIdentifier("board.name")
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
            .navigationTitle(board == nil ? "新建任务栏" : "重命名任务栏").navigationBarTitleDisplayMode(.inline)
            .onAppear { name = board?.title ?? "" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let succeeded = store.change { doc in
                            if let board, let i = doc.boards.firstIndex(where: { $0.id == board.id }) {
                                doc.boards[i].title = name.trimmingCharacters(in: .whitespacesAndNewlines); doc.boards[i].updatedAt = .now
                            } else { doc.boards.append(TaskBoard(title: name.trimmingCharacters(in: .whitespacesAndNewlines))) }
                        }
                        if succeeded { dismiss() } else { errorText = store.errorMessage; store.errorMessage = nil }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.presentationDetents([.medium])
    }
}

struct BoardDetailView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let boardID: UUID
    @State private var renaming = false
    @State private var deleting = false
    var body: some View {
        if let board = store.document.boards.first(where: { $0.id == boardID }) {
            TaskListView(filter: .board(boardID), title: board.title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("任务栏操作", systemImage: "ellipsis") {
                            Button("重命名") { renaming = true }
                            Button("归档任务栏") { updateBoard { $0.archivedAt = .now } }
                            Button("移到废纸篓", role: .destructive) { deleting = true }
                        }
                    }
                }
                .sheet(isPresented: $renaming) { BoardEditor(board: board) }
                .confirmationDialog("任务栏和其中的任务将进入废纸篓，30 天内可以恢复。", isPresented: $deleting, titleVisibility: .visible) {
                    Button("移到废纸篓", role: .destructive) { updateBoard { $0.deletedAt = .now } }
                }
        }
    }
    private func updateBoard(_ edit: (inout TaskBoard) -> Void) {
        if store.change({ doc in if let i = doc.boards.firstIndex(where: { $0.id == boardID }) { edit(&doc.boards[i]) } }) { dismiss() }
    }
}

struct DeadlineLink: View {
    @Environment(TaskStore.self) private var store
    let occurrence: DeadlineOccurrence
    var body: some View {
        NavigationLink {
            TaskDetailView(taskID: occurrence.taskID, initialStepID: occurrence.stepID, initialPersonID: occurrence.personID)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(occurrence.title).foregroundStyle(.primary)
                if let id = occurrence.personID, let name = store.document.people.first(where: { $0.id == id })?.name { Text(name).font(.caption) }
                DeadlineLabel(deadline: occurrence.deadline, kind: occurrence.kind.rawValue + " DDL")
            }
        }
    }
}

struct CalendarPage: View {
    @Environment(TaskStore.self) private var store
    @State private var selected = Calendar.current.startOfDay(for: Date.now)
    @State private var weekly = false
    @State private var kind: DeadlineOccurrence.Kind?
    @State private var personID: UUID?
    private var occurrences: [DeadlineOccurrence] {
        store.document.deadlineOccurrences().filter { (kind == nil || $0.kind == kind) && (personID == nil || $0.personID == personID) }
    }
    private var displayed: [DeadlineOccurrence] {
        let cal = Calendar.current
        if weekly {
            let end = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: selected))!
            return occurrences.filter { $0.deadline.date >= cal.startOfDay(for: selected) && $0.deadline.date < end }
        }
        return occurrences.filter { cal.isDate($0.deadline.date, inSameDayAs: selected) }
    }
    var body: some View {
        List {
            Section {
                Picker("视图", selection: $weekly) { Text("月视图").tag(false); Text("未来 7 天").tag(true) }.pickerStyle(.segmented)
                if !weekly { monthGrid }
                else { DatePicker("起始日期", selection: $selected, displayedComponents: .date) }
                Picker("DDL 类型", selection: $kind) {
                    Text("全部").tag(Optional<DeadlineOccurrence.Kind>.none)
                    ForEach(DeadlineOccurrence.Kind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }.onChange(of: kind) { _, value in if value != .person { personID = nil } }
                if kind == .person {
                    Picker("负责人", selection: $personID) {
                        Text("全部人员").tag(Optional<UUID>.none)
                        ForEach(store.document.people) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            Section(weekly ? "未来 7 天到期" : selected.formatted(date: .abbreviated, time: .omitted)) {
                if displayed.isEmpty { Text("没有符合筛选条件的 DDL").foregroundStyle(.secondary) }
                ForEach(displayed) { DeadlineLink(occurrence: $0) }
            }
        }
    }
    private var monthGrid: some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .month, for: selected)!.start
        let count = cal.range(of: .day, in: .month, for: start)!.count
        let leading = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let names = cal.veryShortStandaloneWeekdaySymbols
        return VStack(spacing: 16) {
            HStack {
                Button("上月", systemImage: "chevron.left") { selected = cal.date(byAdding: .month, value: -1, to: start)! }.labelStyle(.iconOnly)
                Spacer()
                Text(start.formatted(.dateTime.year().month(.wide))).font(.headline)
                Spacer()
                Button("下月", systemImage: "chevron.right") { selected = cal.date(byAdding: .month, value: 1, to: start)! }.labelStyle(.iconOnly)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { Text(names[($0 + cal.firstWeekday - 1) % 7]).font(.caption).foregroundStyle(.secondary) }
                ForEach(0..<(leading + count), id: \.self) { cell in
                    if cell < leading { Color.clear.frame(height: 44) }
                    else {
                        let date = cal.date(byAdding: .day, value: cell - leading, to: start)!
                        let chosen = cal.isDate(date, inSameDayAs: selected)
                        Button { selected = date } label: {
                            VStack(spacing: 3) {
                                Text("\(cell - leading + 1)").font(.subheadline)
                                Circle().fill(occurrences.contains { cal.isDate($0.deadline.date, inSameDayAs: date) } ? ChidiStyle.purple : .clear).frame(width: 4, height: 4)
                            }.frame(maxWidth: .infinity, minHeight: 44)
                                .background(chosen ? ChidiStyle.purple.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
        }
    }
}
