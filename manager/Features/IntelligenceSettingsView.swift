import AppIntents
import SwiftUI

struct IntelligenceSettingsView: View {
    var body: some View {
        List {
            Section("本地 AI") {
                Text(LocalTaskParser.unavailableReason ?? "本地模型可用，可以解析中文任务。")
                Text("文字留在本机处理。解析不会自动创建任务；先核对人员、任务栏、日期和提醒，再确认添加。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Siri 的三个入口") {
                Label("用次第记任务", systemImage: "sparkles")
                Text("说出内容后打开解析预览；若本地模型不可用，可手动填写。").font(.caption)
                Label("用次第往「任务栏」记任务", systemImage: "folder")
                Text("选择已有任务栏，再说任务内容。同名任务栏需要选择。").font(.caption)
                Label("用次第记一下", systemImage: "square.and.pencil")
                Text("把原话直接保存到未分类，不设置 DDL、状态、负责人或四象限。").font(.caption)
            }
            Section {
                ShortcutsLink()
                SiriTipView(intent: SmartCaptureIntent())
            } footer: {
                Text("请先解锁 iPhone。系统识别用语可能受 Siri 语言设置影响，可先在“快捷指令”中运行对应入口。App 内的文字和麦克风入口始终保留。")
            }
        }.navigationTitle("AI 与 Siri").navigationBarTitleDisplayMode(.inline)
    }
}
