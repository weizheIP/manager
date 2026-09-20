import SwiftUI

private enum AppPage: String {
    case overview = "总览", boards = "任务栏", calendar = "日历", people = "人员"

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .boards: "rectangle.stack"
        case .calendar: "calendar"
        case .people: "person.2"
        }
    }
}

struct ContentView: View {
    @Environment(TaskStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @State private var selectedPage: AppPage = .overview
    @State private var showingQuickAdd = false
    @State private var entryRouter = AppEntryRouter.shared
    @State private var captureEntry: AppEntryRequest?

    var body: some View {
        NavigationStack {
            Group {
                switch selectedPage {
                case .overview: OverviewPage()
                case .boards: BoardsPage()
                case .calendar: CalendarPage()
                case .people: PeoplePage()
                }
            }
            .id(selectedPage)
            .background(ChidiStyle.paper)
            .navigationTitle(selectedPage.rawValue)
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
        }
        .sheet(item: Binding(get: { reminders.route }, set: { reminders.route = $0 }), onDismiss: { presentNextEntry() }) { route in
            NavigationStack {
                TaskDetailView(taskID: route.taskID, initialStepID: route.stepID, initialPersonID: route.personID)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { reminders.route = nil } } }
            }
        }
        .tint(ChidiStyle.purple)
        .sheet(isPresented: $showingQuickAdd, onDismiss: { captureEntry = nil; presentNextEntry() }) {
            if let entry = captureEntry, case let .capture(text, boardID, smart) = entry.destination {
                TaskEditor(task: ChidiTask(title: text, boardID: boardID), isNew: true, startParsing: smart).id(entry.id)
            } else { QuickAddSheet() }
        }
        .onChange(of: entryRouter.pending.count, initial: true) { _, _ in presentNextEntry() }
        .alert("数据提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private func presentNextEntry() {
        guard !showingQuickAdd, reminders.route == nil, let entry = entryRouter.pending.first else { return }
        switch entry.destination {
        case .capture: captureEntry = entry; showingQuickAdd = true
        case .detail(let id): reminders.route = ReminderRoute(taskID: id)
        }
        entryRouter.pending.removeFirst()
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            pageButton(.overview)
            pageButton(.boards)
            Button {
                showingQuickAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(width: 48, height: 48)
                    .background(ChidiStyle.purple, in: RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加任务")
            .accessibilityHint("打开任务创建卡片")
            .accessibilityIdentifier("navigation.add")
            pageButton(.calendar)
            pageButton(.people)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(ChidiStyle.purple.opacity(0.12)).frame(height: 0.5)
        }
    }

    private func pageButton(_ page: AppPage) -> some View {
        Button { selectedPage = page } label: {
            VStack(spacing: 5) {
                Image(systemName: page.symbol)
                    .font(.system(size: 21, weight: selectedPage == page ? .semibold : .regular))
                Text(page.rawValue).font(.caption)
            }
            .foregroundStyle(selectedPage == page ? ChidiStyle.purple : .secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
        .accessibilityIdentifier("navigation.\(page)")
    }
}

#Preview {
    ContentView().environment(TaskStore(url: URL.temporaryDirectory.appending(path: "chidi-preview.json"))).environment(ReminderService())
}
