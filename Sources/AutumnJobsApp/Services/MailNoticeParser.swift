import Foundation

struct MailNoticeAnalysis: Equatable {
    var isLikelyNotice = false
    var confidence = 0
    var type: EventType = .other
    var title = ""
    var round: Int?
    var companyName = ""
    var companyCandidates: [String] = []
    var position = ""
    var startsAt: Date?
    var endsAt: Date?
    var format: InterviewFormat = .other
    var meetingURL = ""
    var location = ""
    var interviewer = ""
    var warnings: [String] = []
    var sourceText = ""
}

enum MailNoticeParser {
    private struct ParsedDateTime {
        let start: Date
        let end: Date?
        let defaultedTime: Bool
    }

    private struct DateCandidate {
        let text: String
        let score: Int
    }

    private static let schedulingTerms = [
        "邀请", "安排", "参加", "准时", "请于", "请在", "时间", "地点", "链接", "考试", "作答", "完成"
    ]

    static func analyze(
        _ rawText: String,
        now: Date = Date(),
        calendar inputCalendar: Calendar = .current
    ) -> MailNoticeAnalysis {
        let text = normalize(rawText)
        guard !text.isEmpty else { return MailNoticeAnalysis() }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let subject = extractSubject(from: lines)
        let type = detectType(in: subject.isEmpty ? text : subject + "\n" + text)
        let parsedDate = extractDateTime(from: lines, now: now, calendar: inputCalendar)
        let companyCandidates = extractCompanyCandidates(from: lines, subject: subject)
        let companyName = companyCandidates.first ?? ""
        let position = extractPosition(from: lines)
        let meetingURL = extractMeetingURL(from: text, lines: lines)
        let location = labeledValue(
            labels: ["面试地点", "笔试地点", "考试地点", "测评地点", "线下地点", "地点", "地址"],
            lines: lines
        )
        let interviewer = labeledValue(
            labels: ["面试官", "联系人", "招聘联系人", "HR", "联络人"],
            lines: lines
        )
        let format = detectFormat(in: text, location: location, meetingURL: meetingURL)
        let hasSchedulingTerm = schedulingTerms.contains { text.localizedCaseInsensitiveContains($0) }
        let hasNegativeResult = containsAny(
            ["未通过", "遗憾通知", "感谢您参加", "面试结果", "笔试结果", "流程终止", "不再推进"],
            in: text
        )
        let hasFreshInvitation = containsAny(["邀请您", "邀您", "安排如下", "请参加", "请准时", "请于", "请在"], in: text)
        let isLikelyNotice = type != .other &&
            (parsedDate != nil || hasSchedulingTerm) &&
            (!hasNegativeResult || hasFreshInvitation)

        var confidence = 0
        if type != .other { confidence += 25 }
        if parsedDate != nil { confidence += 25 }
        if !subject.isEmpty { confidence += 8 }
        if !companyName.isEmpty { confidence += 10 }
        if !position.isEmpty { confidence += 10 }
        if !meetingURL.isEmpty || !location.isEmpty { confidence += 7 }
        if hasSchedulingTerm { confidence += 15 }
        if parsedDate?.defaultedTime == true { confidence -= 8 }
        if hasNegativeResult && !hasFreshInvitation { confidence -= 30 }
        confidence = min(100, max(0, confidence))

        var warnings: [String] = []
        if type == .other { warnings.append("没有明确识别到面试、笔试或在线测评关键词。") }
        if parsedDate == nil { warnings.append("没有识别到日程时间，请在保存前手动设置。") }
        if parsedDate?.defaultedTime == true { warnings.append("只识别到日期，已暂按当天 09:00 填入，请核对具体时间。") }
        if companyName.isEmpty { warnings.append("没有可靠识别到公司名称，可搜索已有投递或公司，也可直接输入名称。") }
        if position.isEmpty { warnings.append("没有可靠识别到岗位名称，可从已有投递中手动选择。") }
        if hasNegativeResult && !hasFreshInvitation {
            warnings.append("内容更像结果通知，而不是新的日程邀请，请核对后再保存。")
        }

        return MailNoticeAnalysis(
            isLikelyNotice: isLikelyNotice,
            confidence: confidence,
            type: type,
            title: makeTitle(subject: subject, type: type, text: text),
            round: type.isInterview ? extractRound(from: text) : nil,
            companyName: companyName,
            companyCandidates: companyCandidates,
            position: position,
            startsAt: parsedDate?.start,
            endsAt: parsedDate?.end,
            format: format,
            meetingURL: meetingURL,
            location: location,
            interviewer: interviewer,
            warnings: warnings,
            sourceText: text
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractSubject(from lines: [String]) -> String {
        for line in lines.prefix(12) {
            if let subject = firstCapture(
                #"^(?:主题|邮件主题|subject)\s*[:：]\s*(.+?)\s*$"#,
                in: line
            ) {
                return cleanValue(subject)
            }
        }
        if let first = lines.first,
           first.count <= 100,
           !containsAny(["您好", "你好", "尊敬的", "具体信息", "面试日期", "面试时间"], in: first),
           containsAny(["面试", "笔试", "测评", "assessment", "interview"], in: first) {
            return cleanValue(first)
        }
        return ""
    }

    private static func detectType(in text: String) -> EventType {
        if containsAny(["笔试", "written test", "笔试邀请"], in: text) { return .writtenTest }
        if containsAny(["在线测评", "线上测评", "人才测评", "能力测评", "assessment"], in: text) {
            return .assessment
        }
        if firstMatch(#"(?:\bHR\b|人力|招聘经理)\s*(?:面试|面谈|面)"#, in: text) != nil {
            return .hrInterview
        }
        if containsAny(["面试", "面谈", "interview"], in: text) { return .interview }
        return .other
    }

    private static func extractCompanyCandidates(from lines: [String], subject: String) -> [String] {
        var candidates: [String] = []

        func append(_ value: String) {
            let cleaned = cleanCompanyName(value)
            guard isPlausibleCompanyName(cleaned) else { return }
            guard !candidates.contains(where: { companyNamesAreEquivalent($0, cleaned) }) else { return }
            candidates.append(cleaned)
        }

        append(labeledValue(
            labels: ["公司名称", "应聘公司", "招聘公司", "公司", "企业名称"],
            lines: lines
        ))

        for value in captures(#"【([^】]{2,40})】"#, in: subject) {
            append(value)
        }

        let text = lines.joined(separator: "\n")
        let prosePatterns = [
            // “欢迎您应聘海信集团，现邀请……”是招聘邮件里很常见的写法。
            #"(?:欢迎|感谢)\s*(?:您|你)?\s*(?:来)?(?:申请|应聘|投递|关注)\s*(?:了|的)?\s*[“\"「『【]?\s*([^，,。；;！!\n]{2,40}?)[”\"」』】]?\s*(?=[，,。；;！!\n])"#,
            #"(?:您|你)\s*(?:已|曾|所)?\s*(?:申请|应聘|投递)(?:了|的)?\s*[“\"「『【]?\s*([^，,。；;！!\n]{2,40}?)[”\"」』】]?\s*(?=[，,。；;！!\n])"#,
            #"(?:这里是|我们是|来自|我是来自)\s*[“\"「『【]?\s*([^，,。；;！!\n]{2,40}?)[”\"」』】]?\s*(?=(?:的)?(?:招聘|校招|人力资源|HR|面试|笔试|测评))"#,
            #"(?:受|代表)\s*[“\"「『【]?\s*([^，,。；;！!\n]{2,40}?)[”\"」』】]?\s*(?=(?:邀请|通知))"#
        ]
        for pattern in prosePatterns {
            for value in captures(pattern, in: text) {
                append(value)
            }
        }

        if let value = firstCapture(
            #"^(?:主题|邮件主题|subject)?\s*[:：]?\s*(?:20\d{2}\s*届\s*)?[“\"「『【]?([^：:\-—|｜\n]{2,40}?)[”\"」』】]?\s*(?:校园招聘|招聘)?\s*(?:面试|笔试|测评)(?:邀请|通知)"#,
            in: subject
        ) {
            append(value)
        }

        for line in lines.suffix(12) {
            if let value = firstCapture(
                #"^(.{2,40}?)(?:校园招聘团队|招聘团队|招聘组|人力资源部|人力资源中心)\s*$"#,
                in: line
            ) {
                append(value)
            }
        }
        return candidates
    }

    private static func cleanCompanyName(_ value: String) -> String {
        var result = cleanValue(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: "“”\"「」『』【】<>《》"))
        result = result.replacingOccurrences(
            of: #"^(?:您好|你好)?[！!，,\s]*(?:欢迎|感谢)\s*(?:您|你)?\s*(?:来)?(?:申请|应聘|投递|关注)\s*(?:了|的)?\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"^20\d{2}\s*届\s*"#,
            with: "",
            options: .regularExpression
        )
        for suffix in ["校园招聘团队", "招聘团队", "招聘组", "人力资源部", "人力资源中心", "校园招聘", "招聘", "校招"]
        where result.hasSuffix(suffix) {
            result.removeLast(suffix.count)
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r的"))
    }

    private static func companyNamesAreEquivalent(_ left: String, _ right: String) -> Bool {
        func canonical(_ value: String) -> String {
            var normalized = value.lowercased().unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
                .joined()
            for suffix in ["股份有限公司", "有限责任公司", "有限公司", "集团", "公司"] {
                if normalized.hasSuffix(suffix), normalized.count > suffix.count {
                    normalized.removeLast(suffix.count)
                    break
                }
            }
            return normalized
        }
        let leftCanonical = canonical(left)
        let rightCanonical = canonical(right)
        return !leftCanonical.isEmpty && leftCanonical == rightCanonical
    }

    private static func isPlausibleCompanyName(_ value: String) -> Bool {
        guard (2...40).contains(value.count) else { return false }
        return !containsAny(
            ["面试", "笔试", "测评", "通知", "邀请", "提醒", "应聘", "候选人", "岗位", "职位", "工程师", "面试日期", "面试时间"],
            in: value
        )
    }

    private static func extractPosition(from lines: [String]) -> String {
        let labeled = labeledValue(
            labels: ["应聘岗位", "申请岗位", "投递岗位", "岗位名称", "应聘职位", "申请职位", "职位名称", "岗位", "职位"],
            lines: lines
        )
        if !labeled.isEmpty { return cleanPositionName(labeled) }

        let text = lines.joined(separator: "\n")
        let patterns = [
            // “邀请您就 信动力T计划-算法工程师（大模型）职位进行面试”
            #"(?:诚邀|邀请)\s*(?:您|你)\s*(?:参加|就)\s*[“\"「『【]?\s*([^，,。；;！!\n]{2,80}?)[”\"」』】]?\s*(?:岗位|职位)\s*(?:进行|参加)?\s*(?:面试|笔试|测评|考试)"#,
            #"(?:诚邀|邀请)\s*(?:您|你)\s*参加\s*[“\"「『【]?\s*([^，,。；;！!\n]{2,80}?)[”\"」』】]?\s*(?:面试|笔试|测评|考试)"#,
            #"(?:申请|应聘|投递)(?:的)?\s*[“\"「]?([^”\"」\n，,；;]{2,60})[”\"」]?\s*(?:岗位|职位)"#
        ]
        for pattern in patterns {
            if let value = firstCapture(pattern, in: text) {
                let cleaned = cleanPositionName(value)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return ""
    }

    private static func cleanPositionName(_ value: String) -> String {
        cleanValue(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r“”\"「」『』【】"))
    }

    private static func labeledValue(labels: [String], lines: [String]) -> String {
        for line in lines {
            for label in labels {
                let escaped = NSRegularExpression.escapedPattern(for: label)
                if let value = firstCapture(
                    "^\\s*\(escaped)\\s*[:：]\\s*(.+?)\\s*$",
                    in: line
                ) {
                    return cleanValue(value)
                }
            }
        }
        return ""
    }

    private static func cleanValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r|｜"))
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    }

    private static func extractMeetingURL(from text: String, lines: [String]) -> String {
        let linkLabels = ["会议链接", "面试链接", "笔试链接", "测评链接", "考试链接", "作答链接", "访问链接", "加入会议", "链接", "网址"]
        for line in lines where linkLabels.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
            if let url = firstCapture(#"(https?://[^\s<>\"'，。；;）)\]]+)"#, in: line) {
                return url
            }
        }
        return firstCapture(#"(https?://[^\s<>\"'，。；;）)\]]+)"#, in: text) ?? ""
    }

    private static func detectFormat(in text: String, location: String, meetingURL: String) -> InterviewFormat {
        let combined = text + "\n" + location + "\n" + meetingURL
        if containsAny(["电话面试", "电话沟通", "phone interview"], in: combined) { return .phone }
        if containsAny(
            ["线上", "在线", "视频", "腾讯会议", "飞书会议", "zoom", "teams", "voov", "meeting"],
            in: combined
        ) || !meetingURL.isEmpty {
            return .online
        }
        if containsAny(["线下", "现场", "到场", "到访", "办公楼", "园区"], in: combined) { return .onsite }
        return .other
    }

    private static func makeTitle(subject: String, type: EventType, text: String) -> String {
        if !subject.isEmpty, subject.count <= 100 { return subject }
        switch type {
        case .writtenTest: return "笔试"
        case .assessment: return "在线测评"
        case .hrInterview: return "HR 面试"
        case .interview:
            if let round = extractRound(from: text) { return "第 \(round) 轮面试" }
            if text.localizedCaseInsensitiveContains("终面") { return "终面" }
            return "面试"
        default: return "招聘流程通知"
        }
    }

    private static func extractRound(from text: String) -> Int? {
        if let raw = firstCapture(#"第\s*(\d{1,2})\s*(?:轮|次)"#, in: text) {
            return Int(raw)
        }
        let numerals: [(String, Int)] = [
            ("十", 10), ("九", 9), ("八", 8), ("七", 7), ("六", 6),
            ("五", 5), ("四", 4), ("三", 3), ("二", 2), ("一", 1)
        ]
        for (numeral, number) in numerals where text.contains(numeral + "面") { return number }
        return nil
    }

    private static func extractDateTime(
        from lines: [String],
        now: Date,
        calendar: Calendar
    ) -> ParsedDateTime? {
        var candidates: [DateCandidate] = []
        for (index, line) in lines.enumerated() {
            let lineScore = dateContextScore(for: line)
            candidates.append(DateCandidate(text: line, score: lineScore))
            if index + 1 < lines.count {
                let next = lines[index + 1]
                candidates.append(DateCandidate(
                    text: line + "\n" + next,
                    score: lineScore + dateContextScore(for: next) + 2
                ))
            }
        }

        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            if let parsed = parseDateTime(candidate.text, now: now, calendar: calendar) { return parsed }
        }
        return nil
    }

    private static func dateContextScore(for line: String) -> Int {
        var score = 0
        if containsAny(
            ["面试时间", "笔试时间", "考试时间", "测评时间", "开始时间", "截止时间", "面试日期", "笔试日期"],
            in: line
        ) { score += 12 }
        if containsAny(["面试", "笔试", "测评", "考试", "安排", "截止", "日期", "时间"], in: line) { score += 5 }
        if firstMatch(#"^(?:date|发件时间|发送时间|邮件时间)\s*[:：]"#, in: line) != nil { score -= 15 }
        return score
    }

    private static func parseDateTime(_ text: String, now: Date, calendar inputCalendar: Calendar) -> ParsedDateTime? {
        let calendar = inputCalendar
        let baseDay: Date

        if let match = firstMatch(
            #"(?:(\d{4})\s*(?:年|[./-])\s*)?(\d{1,2})\s*(?:月|[./-])\s*(\d{1,2})\s*(?:日|号)?"#,
            in: text
        ) {
            let currentYear = calendar.component(.year, from: now)
            guard let month = intCapture(match, group: 2, in: text),
                  let day = intCapture(match, group: 3, in: text) else { return nil }
            var year = intCapture(match, group: 1, in: text) ?? currentYear
            let hasExplicitYear = capture(match, group: 1, in: text) != nil
            guard var date = calendar.date(from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )) else { return nil }
            if !hasExplicitYear, date < calendar.startOfDay(for: now) {
                year += 1
                guard let nextYearDate = calendar.date(from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: year,
                    month: month,
                    day: day
                )) else { return nil }
                date = nextYearDate
            }
            baseDay = date
        } else if let relative = firstCapture(#"(今天|明天|后天)"#, in: text) {
            let offset = relative == "今天" ? 0 : (relative == "明天" ? 1 : 2)
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else {
                return nil
            }
            baseDay = date
        } else {
            return nil
        }

        let timeMatches = matches(
            #"(上午|下午|晚上|中午|凌晨|am|pm)?\s*(\d{1,2})\s*(?::|：|点|时)\s*(\d{1,2})?\s*(?:分)?\s*(am|pm)?"#,
            in: text
        )
        guard let firstTime = timeMatches.first else {
            guard let defaultStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: baseDay) else { return nil }
            return ParsedDateTime(start: defaultStart, end: nil, defaultedTime: true)
        }

        guard let start = date(
            on: baseDay,
            match: firstTime,
            text: text,
            calendar: calendar
        ) else { return nil }

        var end: Date?
        if timeMatches.count > 1 {
            let secondTime = timeMatches[1]
            let nsText = text as NSString
            let separatorLocation = firstTime.range.location + firstTime.range.length
            let separatorLength = max(0, secondTime.range.location - separatorLocation)
            let between = nsText.substring(with: NSRange(location: separatorLocation, length: separatorLength))
            if between.count <= 16,
               firstMatch(#"[-–—至到~～]"#, in: between) != nil,
               var parsedEnd = date(on: baseDay, match: secondTime, text: text, calendar: calendar) {
                if parsedEnd < start {
                    if !hasMeridiem(secondTime, in: text),
                       isPM(firstTime, in: text),
                       let afternoonEnd = calendar.date(byAdding: .hour, value: 12, to: parsedEnd),
                       afternoonEnd > start {
                        parsedEnd = afternoonEnd
                    } else if let nextDay = calendar.date(byAdding: .day, value: 1, to: parsedEnd) {
                        parsedEnd = nextDay
                    }
                }
                end = parsedEnd
            }
        }

        return ParsedDateTime(start: start, end: end, defaultedTime: false)
    }

    private static func date(
        on baseDay: Date,
        match: NSTextCheckingResult,
        text: String,
        calendar: Calendar
    ) -> Date? {
        guard var hour = intCapture(match, group: 2, in: text) else { return nil }
        let minute = intCapture(match, group: 3, in: text) ?? 0
        let prefix = capture(match, group: 1, in: text)?.lowercased() ?? ""
        let suffix = capture(match, group: 4, in: text)?.lowercased() ?? ""
        let meridiem = suffix.isEmpty ? prefix : suffix

        if ["下午", "晚上", "中午", "pm"].contains(meridiem), hour < 12 { hour += 12 }
        if ["上午", "凌晨", "am"].contains(meridiem), hour == 12 { hour = 0 }
        guard (0...24).contains(hour), (0...59).contains(minute) else { return nil }

        if hour == 24 {
            guard minute == 0,
                  let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: baseDay) else { return nil }
            return calendar.date(byAdding: .day, value: 1, to: midnight)
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDay)
    }

    private static func hasMeridiem(_ match: NSTextCheckingResult, in text: String) -> Bool {
        capture(match, group: 1, in: text) != nil || capture(match, group: 4, in: text) != nil
    }

    private static func isPM(_ match: NSTextCheckingResult, in text: String) -> Bool {
        let prefix = capture(match, group: 1, in: text)?.lowercased() ?? ""
        let suffix = capture(match, group: 4, in: text)?.lowercased() ?? ""
        return ["下午", "晚上", "中午", "pm"].contains(prefix) || suffix == "pm"
    }

    private static func containsAny(_ needles: [String], in text: String) -> Bool {
        needles.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let match = firstMatch(pattern, in: text) else { return nil }
        return capture(match, group: 1, in: text)
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        matches(pattern, in: text).compactMap { capture($0, group: 1, in: text) }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        matches(pattern, in: text).first
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func capture(_ match: NSTextCheckingResult, group: Int, in text: String) -> String? {
        guard group < match.numberOfRanges else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func intCapture(_ match: NSTextCheckingResult, group: Int, in text: String) -> Int? {
        capture(match, group: group, in: text).flatMap(Int.init)
    }
}
