import SwiftUI

struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var taskName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("先记下来，慢慢理清。")
                        .font(.title2.weight(.medium))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("任务名称").font(.subheadline.weight(.medium))
                        TextField("有什么需要记下的事？", text: $taskName, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(18)
                            .background(ChidiStyle.card, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("任务名称")
                            .accessibilityIdentifier("quickAdd.name")
                    }
                    Label("当前为功能预览，输入内容暂不保存。", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("添加任务 · 即将开放")
                        .font(.headline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(ChidiStyle.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ChidiStyle.paper)
            .navigationTitle("记下一件事")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("quickAdd.close")
                }
            }
        }
        .tint(ChidiStyle.purple)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
