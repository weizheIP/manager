import XCTest
@testable import ChidiCore

final class NaturalLanguageTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 28800)!; return value
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 13))! }

    func testPRDExampleProducesGroundedOptionalFields() throws {
        let source = "明天下午5点让张三和李四确认包装报价，重要紧急，放新品上市，提前2小时强提醒。"
        let raw = TaskExtraction(title: "确认包装报价", board: "新品上市", quadrant: "重要紧急", deadline: "明天下午5点", people: ["张三", "李四"], reminders: ["提前2小时强提醒"])
        let proposal = NaturalLanguageDraft.prepare(raw, source: source, now: now, calendar: calendar)
        XCTAssertEqual(proposal.task.title, "确认包装报价")
        XCTAssertNil(proposal.task.status)
        XCTAssertEqual(proposal.task.quadrant, .importantUrgent)
        XCTAssertEqual(proposal.peopleNames, ["张三", "李四"])
        XCTAssertEqual(proposal.boardName, "新品上市")
        let ddl = try XCTUnwrap(proposal.task.deadline)
        XCTAssertEqual(calendar.component(.day, from: ddl.date), 21)
        XCTAssertEqual(calendar.component(.hour, from: ddl.date), 17)
        XCTAssertEqual(ddl.reminders.first?.kind, .strong)
        XCTAssertEqual(ddl.reminders.first?.amount, 2)
        XCTAssertTrue(proposal.task.assignments.isEmpty, "Names are unresolved until user confirmation")
        XCTAssertTrue(proposal.warnings.isEmpty)
    }

    func testUnmentionedFieldsAreRejectedRatherThanDefaulted() {
        let raw = TaskExtraction(title: "寄资料", board: "工作", quadrant: "重要紧急", status: "待处理", deadline: "明天", people: ["我"], reminders: ["提前1小时"], notes: "自动补充", steps: [StepExtraction(title: "打印")])
        let proposal = NaturalLanguageDraft.prepare(raw, source: "寄资料", now: now, calendar: calendar)
        XCTAssertNil(proposal.boardName)
        XCTAssertNil(proposal.task.quadrant)
        XCTAssertNil(proposal.task.status)
        XCTAssertNil(proposal.task.deadline)
        XCTAssertTrue(proposal.peopleNames.isEmpty)
        XCTAssertTrue(proposal.task.steps.isEmpty)
        XCTAssertTrue(proposal.task.notes.isEmpty)
        XCTAssertFalse(proposal.warnings.isEmpty)
    }

    func testNegatedAndPartialQuadrantMentionsAreNotAccepted() {
        let proposal = NaturalLanguageDraft.prepare(TaskExtraction(title: "寄件", quadrant: "重要不紧急", deadline: "明天", people: ["张三"]), source: "寄件，不重要不紧急，不需要在明天完成，不让张三", now: now, calendar: calendar)
        XCTAssertNil(proposal.task.quadrant)
        XCTAssertNil(proposal.task.deadline)
        XCTAssertTrue(proposal.peopleNames.isEmpty)

        let trailing = NaturalLanguageDraft.prepare(TaskExtraction(title: "寄件", deadline: "明天", people: ["张三"]), source: "寄件，明天不用做，张三不用负责", now: now, calendar: calendar)
        XCTAssertNil(trailing.task.deadline)
        XCTAssertTrue(trailing.peopleNames.isEmpty)
    }

    func testPersonalDeadlineNeverBecomesTaskDeadlineAndAliasesPreserveIt() throws {
        let source = "交报告，张三和老张负责，张三明天下午5点交，提前1小时提醒"
        let raw = TaskExtraction(title: "交报告", people: ["张三", "老张"], personalDeadlines: [PersonalDeadlineExtraction(name: "张三", deadline: "明天下午5点", reminders: ["提前1小时提醒"])])
        let proposal = NaturalLanguageDraft.prepare(raw, source: source, now: now, calendar: calendar)
        XCTAssertNil(proposal.task.deadline)
        let person = UUID()
        let task = try proposal.resolvedTask(boardID: nil, people: ["张三": person, "老张": person])
        XCTAssertEqual(task.assignments.count, 1)
        XCTAssertEqual(task.assignments[0].deadline?.reminders.first?.amount, 1)
        XCTAssertNil(task.deadline)
        var conflicting = proposal
        conflicting.taskPersonalDeadlines["老张"] = Deadline(date: now)
        XCTAssertThrowsError(try conflicting.resolvedTask(boardID: nil, people: ["张三": person, "老张": person]))
    }

    func testNameOnlyInputStaysNameOnly() {
        let proposal = NaturalLanguageDraft.prepare(TaskExtraction(title: "买纸"), source: "买纸", now: now, calendar: calendar)
        XCTAssertNil(proposal.task.deadline)
        XCTAssertNil(proposal.task.status)
        XCTAssertNil(proposal.task.quadrant)
        XCTAssertNil(proposal.task.boardID)
        XCTAssertTrue(proposal.task.assignments.isEmpty)
        XCTAssertTrue(proposal.task.steps.isEmpty)
    }

    func testDateOnlyAmbiguityInvalidDatesAndRanges() throws {
        let dateOnly = try XCTUnwrap(ExplicitDateParser.parse("9月30日", now: now, calendar: calendar))
        XCTAssertFalse(dateOnly.includesTime)
        for phrase in ["尽快", "有空时", "明天下午", "2026年2月30日", "明天25:00", "明天17:61", "周一到周三", "明天3点到5点"] {
            XCTAssertNil(ExplicitDateParser.parse(phrase, now: now, calendar: calendar), phrase)
        }
        XCTAssertNotNil(ExplicitDateParser.parse("明天下午5点到期", now: now, calendar: calendar))
    }

    func testRelativeDatesRespectCalendarRolloverAndExplicitTime() throws {
        let yearEnd = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23))!
        let tomorrow = try XCTUnwrap(ExplicitDateParser.parse("明天下午三点半", now: yearEnd, calendar: calendar))
        XCTAssertEqual(calendar.component(.year, from: tomorrow.date), 2027)
        XCTAssertEqual(calendar.component(.month, from: tomorrow.date), 1)
        XCTAssertEqual(calendar.component(.hour, from: tomorrow.date), 15)
        XCTAssertEqual(calendar.component(.minute, from: tomorrow.date), 30)
        let monday = try XCTUnwrap(ExplicitDateParser.parse("下周一17:00", now: now, calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: monday.date), 21)
    }

    func testUnsupportedOrAmbiguousTimeCannotSilentlyBecomeDateOnly() {
        for phrase in ["明天5pm", "明天17:00 UTC", "明天上午12点", "明天晚上12点", "明天早上", "明天凌晨", "明天3点", "明天12点", "明天三五点", "明天或后天", "明天一十二点", "明天17:00:30"] {
            XCTAssertNil(ExplicitDateParser.parse(phrase, now: now, calendar: calendar), phrase)
        }
        XCTAssertNotNil(ExplicitDateParser.parse("明天上午九点", now: now, calendar: calendar))
        XCTAssertNotNil(ExplicitDateParser.parse("明天中午12点", now: now, calendar: calendar))
        XCTAssertNotNil(ExplicitDateParser.parse("明天03:00", now: now, calendar: calendar))
        XCTAssertNotNil(ExplicitDateParser.parse("明天17点", now: now, calendar: calendar))
        XCTAssertNotNil(ExplicitDateParser.parse("截止明天下午5点前", now: now, calendar: calendar))
    }

    func testMalformedNumbersAndCompoundOffsetsRequireConfirmation() {
        for value in ["三五", "一百五", "十十", "百百", "零十", "一十二", "-1", "1.5"] { XCTAssertNil(ChineseNumber.parse(value), value) }
        XCTAssertEqual(ChineseNumber.parse("两百零三"), 203)
        XCTAssertEqual(ChineseNumber.parse("一百二十三"), 123)
        XCTAssertEqual(ChineseNumber.parse("二十五"), 25)
        for phrase in ["提前1小时30分钟", "提前半小时", "提前三五分钟", "提前1.5小时", "不要提前1小时", "提前1小时或2小时"] {
            XCTAssertNil(ExplicitReminderParser.parse(phrase), phrase)
        }
    }

    func testReminderRequiresExplicitOffsetAndUnit() {
        XCTAssertNil(ExplicitReminderParser.parse("提醒一下"))
        XCTAssertNil(ExplicitReminderParser.parse("提前提醒"))
        XCTAssertEqual(ExplicitReminderParser.parse("提前两周普通提醒")?.unit, .weeks)
        XCTAssertEqual(ExplicitReminderParser.parse("提前两周普通提醒")?.amount, 2)
        XCTAssertEqual(ExplicitReminderParser.parse("截止时强提醒")?.kind, .strong)
        XCTAssertEqual(ExplicitReminderParser.parse("截止时强提醒")?.amount, 0)
    }

    func testStepOwnersAndDeadlinesStayScopedToTheirSteps() throws {
        let source = "整理资料，步骤先核对，张三负责，明天17点；再寄出，李四负责，后天。"
        let raw = TaskExtraction(title: "整理资料", steps: [StepExtraction(title: "核对", deadline: "明天17点", people: ["张三"]), StepExtraction(title: "寄出", deadline: "后天", people: ["李四"])])
        let proposal = NaturalLanguageDraft.prepare(raw, source: source, now: now, calendar: calendar)
        XCTAssertNil(proposal.task.deadline)
        XCTAssertTrue(proposal.taskPeople.isEmpty)
        XCTAssertEqual(proposal.task.steps.count, 2)
        XCTAssertEqual(proposal.stepPeople[proposal.task.steps[0].id], ["张三"])
        XCTAssertEqual(proposal.stepPeople[proposal.task.steps[1].id], ["李四"])
    }

    func testDependenciesRequireExplicitRelationshipLanguage() {
        let raw = TaskExtraction(title: "寄材料", steps: [
            StepExtraction(title: "核对"),
            StepExtraction(title: "寄出", predecessors: ["核对"])
        ])
        let invented = NaturalLanguageDraft.prepare(raw, source: "寄材料，步骤核对和寄出。", now: now, calendar: calendar)
        XCTAssertTrue(invented.task.steps[1].predecessorIDs.isEmpty)
        XCTAssertTrue(invented.warnings.contains { $0.contains("没有明确原文依据") })

        let explicit = NaturalLanguageDraft.prepare(raw, source: "寄材料，先核对，再寄出。", now: now, calendar: calendar)
        XCTAssertEqual(explicit.task.steps[1].predecessorIDs, [explicit.task.steps[0].id])
    }
}
