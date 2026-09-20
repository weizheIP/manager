import SwiftUI

struct DailyReadingCard: View {
    @State private var showingSource = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let reading = DailyReading.reading(on: context.date)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("次 第").tracking(6)
                    Spacer()
                    Text("每日道德经")
                }.font(.caption).foregroundStyle(ChidiStyle.purple)
                Text(reading.original).font(.system(.title2, design: .serif)).lineSpacing(9)
                    .fixedSize(horizontal: false, vertical: true)
                Text("《道德经》· 第\(reading.chapter)章").font(.caption).foregroundStyle(.secondary)
                Text(reading.explanation).font(.subheadline).lineSpacing(5)
                HStack {
                    Text("事有次第，心自从容").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("原文来源", systemImage: "info.circle") { showingSource = true }
                        .labelStyle(.iconOnly).font(.caption)
                }
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background { InkLandscape().background(ChidiStyle.card) }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .sheet(isPresented: $showingSource) {
                NavigationStack {
                    List {
                        Section("今日原文") {
                            Text(reading.original).font(.title3)
                            Text("《道德经》王弼本 · 第\(reading.chapter)章节选")
                        }
                        Section("白话理解") { Text(reading.explanation) }
                        Section {
                            Text("原文保留所据版本字形；白话是次第的简短释义。每日从已核对的节选库轮换，离线也能阅读。")
                            Link("查看王弼本原文", destination: reading.sourceURL)
                        }
                    }.navigationTitle("每日阅读").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { showingSource = false } } }
                }.presentationDetents([.medium, .large])
            }
        }
    }
}
