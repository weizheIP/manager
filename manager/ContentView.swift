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
    @State private var selectedPage: AppPage = .overview
    @State private var showingQuickAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("功能预览 · 任务管理即将开放", systemImage: "sparkle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    switch selectedPage {
                    case .overview: OverviewPage()
                    case .boards: BoardsPage()
                    case .calendar: CalendarPage()
                    case .people: PeoplePage()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .id(selectedPage)
            .background(ChidiStyle.paper)
            .navigationTitle(selectedPage.rawValue)
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
        }
        .tint(ChidiStyle.purple)
        .sheet(isPresented: $showingQuickAdd) { QuickAddSheet() }
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
    ContentView()
}
