import Foundation

struct JDParseResult: Equatable {
    var companyName = ""
    var position = ""
    var location = ""
    var category = ""
    var deadline: Date?
    var requirements = ""

    var recognizedFieldCount: Int {
        [companyName, position, location, category, requirements]
            .filter { !$0.isEmpty }.count + (deadline == nil ? 0 : 1)
    }
}

enum JDParsingService {
    private static let knownLocations = [
        "北京", "上海", "深圳", "广州", "杭州", "成都", "南京", "武汉", "西安",
        "苏州", "天津", "重庆", "长沙", "郑州", "厦门", "青岛", "宁波", "无锡", "合肥",
        "济南", "福州", "东莞", "珠海", "香港", "全国", "远程"
    ]

    static func analyze(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> JDParseResult {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.contains(where: { !$0.isEmpty }) else { return JDParseResult() }

        var result = JDParseResult()
        result.companyName = labelledValue(
            in: lines,
            labels: ["公司名称", "企业名称", "招聘公司", "公司", "company"]
        )
        result.position = labelledValue(
            in: lines,
            labels: ["岗位名称", "职位名称", "应聘岗位", "招聘岗位", "岗位", "职位", "job title", "position"]
        )
        result.location = labelledValue(
            in: lines,
            labels: ["工作地点", "办公地点", "岗位地点", "工作地", "地点", "location"]
        )
        result.category = labelledValue(
            in: lines,
            labels: ["岗位类别", "职位类别", "职能类别", "岗位类型", "职位类型", "category"]
        )
        result.requirements = requirementsSection(in: lines)

        let titleParts = inferredTitleParts(from: lines)
        if result.companyName.isEmpty { result.companyName = titleParts.company }
        if result.position.isEmpty { result.position = titleParts.position }
        if result.location.isEmpty { result.location = titleParts.location }

        result.companyName = cleanedValue(result.companyName)
        result.position = cleanedValue(result.position)
        result.location = cleanedLocation(result.location)
        result.category = normalizedCategory(explicit: result.category, position: result.position)

        let deadlineText = labelledValue(
            in: lines,
            labels: ["投递截止时间", "投递截止日期", "申请截止日期", "申请截止", "截止时间", "截止日期", "截止", "deadline"]
        )
        let deadlineSource = deadlineText.isEmpty
            ? (lines.first(where: { $0.contains("截止") || $0.lowercased().contains("deadline") }) ?? "")
            : deadlineText
        result.deadline = parseDate(deadlineSource, now: now, calendar: calendar)
        return result
    }

    private static func labelledValue(in lines: [String], labels: [String]) -> String {
        let alternatives = labels
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern = #"^\s*(?:"# + alternatives + #")\s*[:：]\s*(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return "" }
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let valueRange = Range(match.range(at: 1), in: line) else { continue }
            return String(line[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let headingPattern = #"^\s*(?:"# + alternatives + #")\s*[:：]?\s*$"#
        if let headingRegex = try? NSRegularExpression(pattern: headingPattern, options: [.caseInsensitive]) {
            for index in lines.indices {
                let line = lines[index]
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard headingRegex.firstMatch(in: line, range: range) != nil else { continue }
                if let value = lines.dropFirst(index + 1).first(where: { !$0.isEmpty }) {
                    return value
                }
            }
        }
        return ""
    }

    private static func inferredTitleParts(from lines: [String]) -> (company: String, position: String, location: String) {
        let visible = Array(lines.filter { !$0.isEmpty }.prefix(8))
        var company = ""
        var position = ""
        var location = ""

        if let first = visible.first,
           let regex = try? NSRegularExpression(pattern: #"^[【\[]([^】\]]{2,40})[】\]]\s*(.*)$"#),
           let match = regex.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)) {
            if let companyRange = Range(match.range(at: 1), in: first) {
                company = String(first[companyRange])
            }
            if let positionRange = Range(match.range(at: 2), in: first) {
                position = String(first[positionRange]).trimmingCharacters(in: CharacterSet(charactersIn: " -|｜·"))
            }
        }

        if company.isEmpty || position.isEmpty {
            for line in visible {
                let parts = line.components(separatedBy: CharacterSet(charactersIn: "|｜"))
                    .map { cleanedValue($0) }
                    .filter { !$0.isEmpty }
                guard parts.count >= 2, looksLikePosition(parts[1]) else { continue }
                if company.isEmpty { company = parts[0] }
                if position.isEmpty { position = parts[1] }
                if parts.count >= 3 { location = parts[2] }
                break
            }
        }

        if position.isEmpty, let positionIndex = visible.firstIndex(where: looksLikePosition) {
            position = visible[positionIndex]
            if company.isEmpty, positionIndex > 0 {
                let candidate = visible[positionIndex - 1]
                if !candidate.contains("："), !candidate.contains(":"), candidate.count <= 50 {
                    company = candidate
                }
            }
            if location.isEmpty, positionIndex + 1 < visible.count {
                let candidate = visible[positionIndex + 1]
                let matches = knownLocations.filter(candidate.contains)
                if !matches.isEmpty { location = matches.joined(separator: " / ") }
            }
        }
        if location.isEmpty {
            let titleLine = visible.first(where: { $0.contains(position) }) ?? ""
            location = knownLocations.filter(titleLine.contains).joined(separator: " / ")
        }
        return (company, position, location)
    }

    private static func requirementsSection(in lines: [String]) -> String {
        let startHeadings = ["岗位要求", "任职要求", "职位要求", "任职资格", "任职条件", "requirements", "qualifications"]
        let stopHeadings = [
            "岗位职责", "职位职责", "工作职责", "工作内容", "职位描述", "薪资福利", "福利待遇",
            "加分项", "申请方式", "投递方式", "工作地点", "关于我们", "公司介绍",
            "投递截止时间", "投递截止日期", "申请截止日期", "申请截止",
            "截止时间", "截止日期", "deadline", "benefits"
        ]
        guard let start = lines.firstIndex(where: { line in
            startHeadings.contains { isHeading(line, named: $0) }
        }) else { return "" }

        var captured: [String] = []
        if let separator = lines[start].firstIndex(where: { $0 == ":" || $0 == "：" }) {
            let tail = lines[start][lines[start].index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { captured.append(tail) }
        }
        for line in lines.dropFirst(start + 1) {
            if stopHeadings.contains(where: { isHeading(line, named: $0) }) { break }
            if startHeadings.contains(where: { isHeading(line, named: $0) }) { continue }
            if !line.isEmpty { captured.append(line) }
        }
        return captured.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isHeading(_ line: String, named heading: String) -> Bool {
        let normalized = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let target = heading.lowercased()
        return normalized == target || normalized == "\(target):" || normalized == "\(target)：" ||
            normalized.hasPrefix("\(target):") || normalized.hasPrefix("\(target)：")
    }

    private static func parseDate(_ text: String, now: Date, calendar: Calendar) -> Date? {
        guard !text.isEmpty else { return nil }
        let pattern = #"(?:(20\d{2})\s*[年./-]\s*)?(\d{1,2})\s*[月./-]\s*(\d{1,2})\s*日?(?:\s*(\d{1,2})\s*[:：]\s*(\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let month = integerCapture(2, match: match, text: text),
              let day = integerCapture(3, match: match, text: text) else { return nil }
        let hour = integerCapture(4, match: match, text: text) ?? 23
        let minute = integerCapture(5, match: match, text: text) ?? 59
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var year = integerCapture(1, match: match, text: text) ?? calendar.component(.year, from: now)
        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard var date = calendar.date(from: components) else { return nil }
        guard calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        if integerCapture(1, match: match, text: text) == nil,
           date < calendar.startOfDay(for: now) {
            year += 1
            components.year = year
            date = calendar.date(from: components) ?? date
        }
        return date
    }

    private static func integerCapture(_ index: Int, match: NSTextCheckingResult, text: String) -> Int? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[range])
    }

    private static func normalizedCategory(explicit: String, position: String) -> String {
        let source = "\(explicit) \(position)".lowercased()
        let mappings: [(String, [String])] = [
            ("管培生", ["管培", "management trainee"]),
            ("算法", ["算法", "machine learning", "机器学习", "深度学习"]),
            ("数据", ["数据分析", "数据科学", "数据工程", "data scientist", "data analyst"]),
            ("产品", ["产品经理", "产品运营"]),
            ("设计", ["ui设计", "ux", "交互设计", "视觉设计", "设计师"]),
            ("测试", ["测试", "qa工程师"]),
            ("运营", ["运营"]),
            ("市场", ["市场", "品牌", "公关"]),
            ("销售", ["销售", "商务拓展", "bd经理"]),
            ("职能", ["人力资源", "hr", "财务", "法务", "行政", "采购"]),
            ("研发", ["开发", "研发", "后端", "前端", "客户端", "软件工程师", "ios", "android"])
        ]
        return mappings.first(where: { mapping in mapping.1.contains(where: source.contains) })?.0 ?? cleanedValue(explicit)
    }

    private static func looksLikePosition(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return ["工程师", "经理", "实习生", "管培生", "顾问", "专员", "设计师", "分析师", "developer", "engineer"]
            .contains(where: lowercased.contains)
    }

    private static func cleanedLocation(_ value: String) -> String {
        let cleaned = cleanedValue(value)
        let matched = knownLocations.filter(cleaned.contains)
        return matched.isEmpty ? cleaned : matched.joined(separator: " / ")
    }

    private static func cleanedValue(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "|｜·,，;；")
        ))
    }
}
