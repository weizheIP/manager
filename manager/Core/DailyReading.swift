import Foundation

struct DailyReading: Identifiable, Sendable {
    let id: Int
    let chapter: String
    let original: String
    let explanation: String
    var sourceURL: URL {
        URL(string: "https://zh.wikisource.org/wiki/道德經_(王弼本)#\(chapter)章")!
    }

    // Public-domain original excerpts, checked against the Wang Bi edition on 2026-09-20.
    // Keep original characters. Explanations below are editorial paraphrases, not quotations.
    static let library: [DailyReading] = [
        .init(id: 1, chapter: "八", original: "上善若水。", explanation: "好的品格如水，滋养万物而不争先。"),
        .init(id: 2, chapter: "十五", original: "孰能濁以靜之徐清？", explanation: "让纷乱慢慢沉静，事情才会逐渐清楚。"),
        .init(id: 3, chapter: "三十三", original: "知人者智，自知者明。", explanation: "了解别人是智慧，认清自己更是明察。"),
        .init(id: 4, chapter: "四十四", original: "知足不辱，知止不殆，可以長久。", explanation: "懂得知足与适可而止，才能走得长远。"),
        .init(id: 5, chapter: "四十五", original: "大成若缺，其用不弊。", explanation: "真正的圆满未必外表完美，却能长久发挥作用。"),
        .init(id: 6, chapter: "四十八", original: "為學日益，為道日損。", explanation: "学习在于不断积累，体悟道则在于减少执着。"),
        .init(id: 7, chapter: "六十四", original: "千里之行，始於足下。", explanation: "再远的路，也从眼前这一步开始。"),
        .init(id: 8, chapter: "六十四", original: "慎終如始，則無敗事。", explanation: "接近完成时，也保持开始时的认真。")
    ]

    static func reading(on date: Date, timeZone: TimeZone = .current) -> DailyReading {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 1
        return library[(day - 1) % library.count]
    }
}
