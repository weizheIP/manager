import SwiftUI

struct OverviewPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 18) {
                Text("次 第")
                    .font(.caption.weight(.semibold))
                    .tracking(6)
                    .foregroundStyle(ChidiStyle.purple)
                Text("事有次第\n心自从容")
                    .font(.system(.largeTitle, design: .serif))
                    .lineSpacing(8)
                Text("每日道德经 · 原文内容准备中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { InkLandscape().background(ChidiStyle.card) }
            .clipShape(RoundedRectangle(cornerRadius: 24))

            ShellSection(title: "今日重点") {
                EmptyCard(symbol: "sun.horizon", title: "把心思放在今天", message: "今天需要关注的任务，将在这里汇集。")
            }
            ShellSection(title: "四象限") { QuadrantPreview() }
            ShellSection(title: "即将到期") {
                EmptyCard(symbol: "clock", title: "为接下来的事留一点余地", message: "从明天起，未来 7 天到期的事项将在这里展示。")
            }
            ShellSection(title: "最近任务栏") {
                EmptyCard(symbol: "rectangle.stack", title: "让事务各有归处", message: "最近使用的任务栏，将出现在这里。")
            }
        }
    }
}

private struct QuadrantPreview: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let quadrants: [(title: String, action: String, color: Color)] = [
        ("重要紧急", "立马亲自做", .red),
        ("重要不紧急", "延后亲自做", .orange),
        ("不重要但紧急", "交给AI做", .blue),
        ("不重要不紧急", "有空再做", .gray)
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
            ForEach(quadrants, id: \.title) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Circle().fill(item.color.opacity(0.55)).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(item.title).font(.subheadline.weight(.medium))
                    Text(item.action).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(item.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

struct BoardsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("把相关的事，放在一起。")
                .font(.title3).foregroundStyle(.secondary)
            EmptyCard(symbol: "rectangle.stack.badge.plus", title: "你的第一栏，留给重要的事", message: "为项目、生活或一段目标建立任务栏，让每件事都能找到自己的位置。")
            ShellSection(title: "从简单开始") {
                Text("任务可以属于一个任务栏，也可以暂时未分类。只记下名称，就足够开始。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct CalendarPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(Date.now.formatted(.dateTime.year().month(.wide).day().locale(Locale(identifier: "zh_CN"))))
                .font(.title3).foregroundStyle(ChidiStyle.purple)
            EmptyCard(symbol: "calendar", title: "看清每一件事的最迟时间", message: "月视图和周视图即将开放。没有固定日期的任务，不会被强行安排到日历里。")
            ShellSection(title: "三种 DDL，清楚区分") {
                VStack(alignment: .leading, spacing: 20) {
                    deadlineLabel("总任务 DDL", detail: "整件事的最迟完成时间", symbol: "square.stack")
                    deadlineLabel("步骤 DDL", detail: "其中一步的最迟完成时间", symbol: "list.number")
                    deadlineLabel("个人 DDL", detail: "每位负责人的独立截止时间", symbol: "person.crop.circle")
                }
            }
        }
    }

    private func deadlineLabel(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(ChidiStyle.purple)
                .frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct PeoplePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("看见每个人手上的事。")
                .font(.title3).foregroundStyle(.secondary)
            EmptyCard(symbol: "person.2", title: "让分工清晰，让协作从容", message: "人员视图将汇集每位负责人负责的任务、步骤，以及各自的 DDL。")
            ShellSection(title: "关注负载，而不只是姓名") {
                Text("进行中、等待中、近期到期的事项，都将在这里一目了然。一个任务也可以由多个人共同负责。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
