import Foundation

/// Model output is untrusted. Fields must quote the input before they can become a proposal.
struct TaskExtraction: Codable, Equatable, Sendable {
    var title: String
    var board: String?
    var quadrant: String?
    var status: String?
    var waitingReason: String?
    var deadline: String?
    var people: [String] = []
    var reminders: [String] = []
    var notes: String?
    var steps: [StepExtraction] = []
    var personalDeadlines: [PersonalDeadlineExtraction] = []
}

struct StepExtraction: Codable, Equatable, Sendable {
    var title: String
    var deadline: String?
    var people: [String] = []
    var reminders: [String] = []
    var personalDeadlines: [PersonalDeadlineExtraction] = []
    var status: String?
    var notes: String?
    var predecessors: [String] = []
}

struct PersonalDeadlineExtraction: Codable, Equatable, Sendable {
    var name: String
    var deadline: String?
    var reminders: [String] = []
}

struct NaturalLanguageDraft: Identifiable, Sendable {
    let id = UUID()
    let source: String
    var task: ChidiTask
    var boardName: String?
    var peopleNames: [String]
    var taskPeople: [String]
    var taskPersonalDeadlines: [String: Deadline]
    var stepPersonalDeadlines: [UUID: [String: Deadline]]
    var stepPeople: [UUID: [String]]
    var warnings: [String]

    func resolvedTask(boardID: UUID?, people mapping: [String: UUID]) throws -> ChidiTask {
        func sameDeadline(_ a: Deadline, _ b: Deadline) -> Bool {
            a.date == b.date && a.includesTime == b.includesTime && a.reminders.count == b.reminders.count && zip(a.reminders, b.reminders).allSatisfy {
                $0.amount == $1.amount && $0.unit == $1.unit && $0.kind == $1.kind
            }
        }
        func assignments(_ names: [String], deadlines: [String: Deadline]) throws -> [Assignment] {
            var result: [Assignment] = []
            for name in names {
                guard let id = mapping[name] else { continue }
                let deadline = deadlines[name]
                if let index = result.firstIndex(where: { $0.personID == id }) {
                    if let deadline, let existing = result[index].deadline, !sameDeadline(existing, deadline) {
                        throw ChidiDataError.invalid("多个称呼对应同一负责人，但个人 DDL 不同。请只保留一个对应关系，再手动核对 DDL。")
                    }
                    if result[index].deadline == nil { result[index].deadline = deadline }
                } else { result.append(Assignment(personID: id, deadline: deadline)) }
            }
            return result
        }
        var result = task
        result.boardID = boardID
        result.assignments = try assignments(taskPeople, deadlines: taskPersonalDeadlines)
        for index in result.steps.indices {
            let id = result.steps[index].id
            result.steps[index].assignments = try assignments(stepPeople[id] ?? [], deadlines: stepPersonalDeadlines[id] ?? [:])
        }
        return result
    }

    static func prepare(_ extraction: TaskExtraction, source: String, now: Date = .now, calendar: Calendar = .current) -> NaturalLanguageDraft {
        var warnings: [String] = []
        func quoted(_ value: String?, label: String) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            var search = source.startIndex..<source.endIndex
            while let range = source.range(of: value, range: search) {
                let prefix = source[..<range.lowerBound]
                let nearby = String(prefix.suffix(16))
                let suffix = String(source[range.upperBound...].prefix(16))
                let checksTrailingNegation = !["任务名称", "步骤名称", "备注", "步骤备注"].contains(label)
                let negatedAfter = checksTrailingNegation
                    && suffix.wholeMatch(of: /[\s，,、：:]*(?:这项|这个|这天|当天)?(?:不是|不要|不设|取消|不让|不用|无需|不需要|暂不|别设|别).*/) != nil
                let negated = nearby.wholeMatch(of: /.*(?:不是|不要|不设|取消|不让|不用|无需|不需要|暂不|别设|别)(?:在|让|由|给|把|设置|安排|选择|指定)?/) != nil
                    || negatedAfter
                    || (label == "四象限" && prefix.hasSuffix("不"))
                if !negated { return value }
                search = range.upperBound..<source.endIndex
            }
            warnings.append("\(label)未找到明确的原文依据，已留空。")
            return nil
        }
        func names(_ values: [String]) -> [String] {
            var seen = Set<String>()
            return values.compactMap { quoted($0, label: "负责人") }.filter { seen.insert($0).inserted }
        }
        func deadline(_ phrase: String?) -> Deadline? {
            guard let phrase = quoted(phrase, label: "DDL") else { return nil }
            guard let result = ExplicitDateParser.parse(phrase, now: now, calendar: calendar) else {
                warnings.append("“\(phrase)”的具体日期或时间还需你确认，DDL 已留空。")
                return nil
            }
            return result
        }
        let title = quoted(extraction.title, label: "任务名称") ?? source.trimmingCharacters(in: .whitespacesAndNewlines)
        var task = ChidiTask(title: title)
        if let phrase = quoted(extraction.quadrant, label: "四象限") {
            let mapping: [String: Quadrant] = ["重要紧急": .importantUrgent, "重要且紧急": .importantUrgent, "重要不紧急": .important, "重要但不紧急": .important, "不重要但紧急": .urgent, "不重要紧急": .urgent, "不重要不紧急": .neither, "不重要也不紧急": .neither]
            task.quadrant = mapping[phrase]
            if task.quadrant == nil { warnings.append("四象限表达还需确认，已留空。") }
        }
        if let phrase = quoted(extraction.status, label: "状态") {
            task.status = WorkStatus.allCases.first { $0.title == phrase }
            if task.status == nil { warnings.append("状态表达还需确认，已留空。") }
        }
        task.waitingReason = quoted(extraction.waitingReason, label: "等待原因") ?? ""
        task.notes = quoted(extraction.notes, label: "备注") ?? ""
        func configuredDeadline(_ phrase: String?, reminders: [String]) -> Deadline? {
            var value = deadline(phrase)
            for raw in reminders {
                guard let phrase = quoted(raw, label: "提醒") else { continue }
                guard let reminder = ExplicitReminderParser.parse(phrase), value != nil else {
                    warnings.append("“\(phrase)”尚不能排定；请先核对 DDL 和提前量。")
                    continue
                }
                value?.reminders.append(reminder)
            }
            return value
        }
        func personalDeadlines(_ values: [PersonalDeadlineExtraction], owners: [String]) -> [String: Deadline] {
            var result: [String: Deadline] = [:]
            for item in values {
                guard owners.contains(item.name) else { warnings.append("个人 DDL 的负责人未明确，已留空。"); continue }
                result[item.name] = configuredDeadline(item.deadline, reminders: item.reminders)
            }
            return result
        }
        task.deadline = configuredDeadline(extraction.deadline, reminders: extraction.reminders)
        let taskPeople = names(extraction.people)
        let taskPersonal = personalDeadlines(extraction.personalDeadlines, owners: taskPeople)
        var stepPeople: [UUID: [String]] = [:]
        var stepPersonal: [UUID: [String: Deadline]] = [:]
        var predecessorNames: [UUID: [String]] = [:]
        for value in extraction.steps.prefix(20) {
            guard let title = quoted(value.title, label: "步骤名称") else { continue }
            var step = TaskStep(title: title, deadline: configuredDeadline(value.deadline, reminders: value.reminders))
            if let status = quoted(value.status, label: "步骤状态") {
                step.status = WorkStatus.allCases.first { $0.title == status }
                if step.status == nil { warnings.append("步骤“\(title)”的状态表达还需确认，已留空。") }
            }
            step.notes = quoted(value.notes, label: "步骤备注") ?? ""
            task.steps.append(step)
            let owners = names(value.people)
            stepPeople[step.id] = owners
            stepPersonal[step.id] = personalDeadlines(value.personalDeadlines, owners: owners)
            predecessorNames[step.id] = value.predecessors
        }
        for index in task.steps.indices {
            for name in predecessorNames[task.steps[index].id] ?? [] {
                guard hasExplicitDependency(predecessor: name, successor: task.steps[index].title, in: source) else {
                    warnings.append("“\(name)”与“\(task.steps[index].title)”的前置关系没有明确原文依据，已留空。")
                    continue
                }
                let matches = task.steps.filter { $0.title == name && $0.id != task.steps[index].id }
                if matches.count == 1 && !task.steps[index].predecessorIDs.contains(matches[0].id) { task.steps[index].predecessorIDs.append(matches[0].id) }
                else { warnings.append("前置步骤“\(name)”无法唯一确定，请手动设置。") }
            }
        }
        if extraction.steps.count > 20 { warnings.append("步骤超过单次解析范围，请分次添加。") }
        let board = quoted(extraction.board, label: "任务栏")
        var allNames = taskPeople
        for step in task.steps { for name in stepPeople[step.id] ?? [] where !allNames.contains(name) { allNames.append(name) } }
        return NaturalLanguageDraft(source: source, task: task, boardName: board, peopleNames: allNames, taskPeople: taskPeople, taskPersonalDeadlines: taskPersonal, stepPersonalDeadlines: stepPersonal, stepPeople: stepPeople, warnings: warnings)
    }

    private static func hasExplicitDependency(predecessor: String, successor: String, in source: String) -> Bool {
        let compact = source.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let direct = [
            "\(successor)依赖\(predecessor)", "\(successor)的前置步骤是\(predecessor)",
            "\(successor)的前置步骤为\(predecessor)", "\(successor)前置\(predecessor)",
            "\(predecessor)完成后再\(successor)", "\(predecessor)后再\(successor)",
            "\(predecessor)之后再\(successor)"
        ]
        if direct.contains(where: compact.contains) { return true }
        for first in ["先\(predecessor)", "先完成\(predecessor)"] {
            if let prior = compact.range(of: first),
               let next = compact.range(of: "再\(successor)", range: prior.upperBound..<compact.endIndex),
               prior.upperBound <= next.lowerBound { return true }
        }
        return false
    }
}

enum ExplicitReminderParser {
    static func parse(_ phrase: String) -> Reminder? {
        let value = phrase.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        guard value.wholeMatch(of: /(?:提前[0-9一二两三四五六七八九十百零]+(?:分钟|小时|天|周)|到期时|截止时)(?:普通提醒|强提醒|提醒|闹钟)?/) != nil else { return nil }
        let strong = value.contains("强提醒") || value.contains("闹钟")
        if value.hasPrefix("到期时") || value.hasPrefix("截止时") { return Reminder(amount: 0, unit: .minutes, kind: strong ? .strong : .ordinary) }
        guard let match = value.firstMatch(of: /提前([0-9一二两三四五六七八九十百零]+)(分钟|小时|天|周)/),
              let amount = ChineseNumber.parse(String(match.1)), (0...100000).contains(amount) else { return nil }
        let unit: Reminder.Unit
        switch String(match.2) { case "分钟": unit = .minutes; case "小时": unit = .hours; case "天": unit = .days; default: unit = .weeks }
        return Reminder(amount: amount, unit: unit, kind: strong ? .strong : .ordinary)
    }
}

enum ChineseNumber {
    static func parse(_ text: String) -> Int? {
        if text.wholeMatch(of: /[0-9]+/) != nil { return Int(text) }
        // Reject ambiguous shorthand (一百五), repeated units and adjacent digits.
        guard text.wholeMatch(of: /(?:[零一二两三四五六七八九]|[二两三四五六七八九]?十[一二三四五六七八九]?|[一二两三四五六七八九]百(?:零[一二三四五六七八九]|[一二三四五六七八九]?十[一二三四五六七八九]?)?)/) != nil else { return nil }
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        var sum = 0, digit = 0
        for character in text {
            if let value = digits[character] { digit = value }
            else if character == "十" { sum += max(1, digit) * 10; digit = 0 }
            else if character == "百" { sum += digit * 100; digit = 0 }
        }
        return sum + digit
    }
}

enum ExplicitDateParser {
    static func parse(_ phrase: String, now: Date, calendar: Calendar) -> Deadline? {
        let phrase = phrase.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        guard phrase.wholeMatch(of: /(?:截止到?|到期时间为?|DDL为?)?(?:大后天|后天|明天|今天|今晚|[0-9一二两三四五六七八九十]+天后|(?:本周|这周|下下周|下周|周|星期)[一二三四五六日天]|[0-9]{4}[-年\/][0-9]{1,2}[-月\/][0-9]{1,2}[日号]?|[0-9]{1,2}月[0-9]{1,2}[日号]?)(?:的)?(?:上午|中午|下午|晚上|凌晨|早上)?(?:[0-9]{1,2}[:：][0-9]{2}|[0-9一二两三四五六七八九十]+[点时](?:半|一刻|三刻|[0-9一二三四五六七八九十]+分?)?)?(?:到期|截止|之前|前)?/) != nil else { return nil }
        let start = calendar.startOfDay(for: now)
        var day: Date?
        // Resolve only a single, explicit civil date. Ambiguous ranges stay unset.
        if phrase.firstMatch(of: /(?:点|时|日|号|\d)\s*(?:到|至|~|～)\s*(?:[0-9一二三四五六七八九十]|上午|下午|晚上)/) != nil || phrase.firstMatch(of: /(?:周|星期)[一二三四五六日天](?:到|至)(?:周|星期)/) != nil { return nil }
        if phrase.contains("大后天") { day = calendar.date(byAdding: .day, value: 3, to: start) }
        else if phrase.contains("后天") { day = calendar.date(byAdding: .day, value: 2, to: start) }
        else if phrase.contains("明天") { day = calendar.date(byAdding: .day, value: 1, to: start) }
        else if phrase.contains("今天") || phrase.contains("今晚") { day = start }
        else if let match = phrase.firstMatch(of: /([0-9一二两三四五六七八九十]+)天后/), let count = ChineseNumber.parse(String(match.1)) {
            day = calendar.date(byAdding: .day, value: count, to: start)
        } else if let match = phrase.firstMatch(of: /(本周|这周|下周|下下周|周|星期)([一二三四五六日天])/), let character = match.2.first {
            let weekdays: [Character: Int] = ["一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6]
            let current = (calendar.component(.weekday, from: now) + 5) % 7
            let target = weekdays[character]!
            let prefix = String(match.1)
            var delta = target - current
            if prefix == "下周" { delta += 7 } else if prefix == "下下周" { delta += 14 }
            else if prefix == "周" || prefix == "星期" { if delta < 0 { delta += 7 } }
            day = calendar.date(byAdding: .day, value: delta, to: start)
        } else if let match = phrase.firstMatch(of: /(\d{4})[-年\/](\d{1,2})[-月\/](\d{1,2})日?/) {
            day = civilDate(year: Int(match.1)!, month: Int(match.2)!, day: Int(match.3)!, calendar: calendar)
        } else if let match = phrase.firstMatch(of: /(\d{1,2})月(\d{1,2})[日号]?/) {
            let year = calendar.component(.year, from: now)
            day = civilDate(year: year, month: Int(match.1)!, day: Int(match.2)!, calendar: calendar)
            // No year was specified: do not silently roll a past date into the next year.
        }
        guard let day else { return nil }
        var hour: Int?, minute = 0
        var usesExplicit24HourClock = false
        if let match = phrase.firstMatch(of: /(\d{1,2})[:：](\d{2})/) {
            hour = Int(match.1); minute = Int(match.2)!; usesExplicit24HourClock = true
        }
        else if let match = phrase.firstMatch(of: /([0-9一二两三四五六七八九十]+)[点时](半|一刻|三刻|[0-9一二三四五六七八九十]+分?)?/) {
            guard let parsedHour = ChineseNumber.parse(String(match.1)) else { return nil }
            hour = parsedHour
            if let part = match.2 {
                switch String(part) {
                case "半": minute = 30
                case "一刻": minute = 15
                case "三刻": minute = 45
                default: guard let value = ChineseNumber.parse(String(part).replacingOccurrences(of: "分", with: "")) else { return nil }; minute = value
                }
            }
        }
        if hour == nil {
            if phrase.contains("中午") || phrase.contains("下午") || phrase.contains("晚上") || phrase.contains("上午") || phrase.contains("今晚") || phrase.contains("早上") || phrase.contains("凌晨") { return nil }
            return Deadline(date: day, includesTime: false)
        }
        let hasPeriod = ["上午", "早上", "中午", "下午", "晚上", "今晚", "凌晨"].contains(where: phrase.contains)
        if !hasPeriod && !usesExplicit24HourClock && (1...12).contains(hour!) { return nil }
        if phrase.contains("上午") || phrase.contains("早上") {
            guard (1...11).contains(hour!) else { return nil }
        } else if phrase.contains("下午") || phrase.contains("晚上") || phrase.contains("今晚") {
            // 12 at night could mean the next civil day. Require a precise replacement.
            guard hour != 12, hour != 0 else { return nil }
            if hour! < 12 { hour! += 12 }
        } else if phrase.contains("中午") {
            guard [11, 12, 1, 2, 13, 14].contains(hour!) else { return nil }
            if hour! < 11 { hour! += 12 }
        } else if phrase.contains("凌晨") {
            if hour == 12 { hour = 0 }
            guard (0...5).contains(hour!) else { return nil }
        }
        guard (0..<24).contains(hour!), (0..<60).contains(minute),
              let date = calendar.date(bySettingHour: hour!, minute: minute, second: 0, of: day),
              calendar.isDate(date, inSameDayAs: day), calendar.component(.hour, from: date) == hour, calendar.component(.minute, from: date) == minute else { return nil }
        return Deadline(date: date, includesTime: true)
    }

    private static func civilDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let result = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: result) == year, calendar.component(.month, from: result) == month,
              calendar.component(.day, from: result) == day else { return nil }
        return result
    }
}
