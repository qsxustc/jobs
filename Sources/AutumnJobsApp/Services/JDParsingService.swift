import Foundation

struct JDParseResult: Equatable {
    var companyName = ""
    var position = ""
    var location = ""
    var category = ""
    var projectName = ""
    var projectType = ""
    var deadline: Date?
    var requirements = ""

    var recognizedFieldCount: Int {
        [companyName, position, location, category, projectName, projectType, requirements]
            .filter { !$0.isEmpty }.count + (deadline == nil ? 0 : 1)
    }
}

enum JDParsingService {
    private static let knownLocations = [
        "北京", "上海", "深圳", "广州", "杭州", "成都", "南京", "武汉", "西安",
        "苏州", "天津", "重庆", "长沙", "郑州", "厦门", "青岛", "宁波", "无锡", "合肥",
        "济南", "福州", "东莞", "珠海", "香港", "澳门", "台北", "全国", "远程"
    ]

    /// Brand names are only considered in company-introduction context. This
    /// keeps offline parsing deterministic while covering JDs that omit an
    /// explicit company field and only say, for example, “字节跳动搜索团队”.
    private static let knownCompanyNames = [
        "阿里巴巴", "蚂蚁集团", "字节跳动", "哔哩哔哩", "小红书", "拼多多", "腾讯",
        "百度", "美团", "京东", "快手", "网易", "华为", "小米", "滴滴", "携程",
        "联想", "海尔", "海信", "荣耀", "OPPO", "vivo", "微软", "谷歌", "亚马逊",
        "英伟达", "英特尔"
    ]

    private static let bodyHeadings = [
        "岗位职责", "职位职责", "工作职责", "工作内容", "岗位描述", "职位描述",
        "岗位要求", "职位要求", "任职要求", "任职资格", "任职条件",
        "job description", "responsibilities", "requirements", "qualifications"
    ]

    static func analyze(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> JDParseResult {
        let lines = normalizedLines(from: text)
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
            labels: [
                "工作地点", "办公地点", "岗位地点", "工作城市", "办公城市", "工作地", "地点",
                "base地点", "base地", "base", "location"
            ]
        )
        result.category = labelledValue(
            in: lines,
            labels: ["岗位类别", "职位类别", "职能类别", "岗位类型", "职位类型", "category"]
        )
        if result.category.isEmpty { result.category = inferredCategory(from: lines) }
        result.projectName = labelledValue(
            in: lines,
            labels: ["招聘项目", "项目名称", "招聘批次", "校招项目", "recruitment program"]
        )
        result.projectType = labelledValue(
            in: lines,
            labels: ["项目类型", "招聘类型", "招聘类别", "recruitment type"]
        )
        result.requirements = requirementsSection(in: lines)

        let titleParts = inferredTitleParts(from: lines)
        if result.companyName.isEmpty { result.companyName = titleParts.company }
        if result.companyName.isEmpty { result.companyName = inferredCompany(from: lines) }
        if result.position.isEmpty { result.position = titleParts.position }
        if result.location.isEmpty { result.location = titleParts.location }

        let projectParts = inferredProject(from: lines)
        if result.projectName.isEmpty { result.projectName = projectParts.name }
        if result.projectType.isEmpty { result.projectType = projectParts.type }

        result.companyName = cleanedValue(result.companyName)
        result.position = cleanedValue(result.position)
        result.location = cleanedLocation(result.location)
        result.category = normalizedCategory(explicit: result.category, position: result.position)
        result.projectName = cleanedValue(result.projectName)
        result.projectType = result.projectType.isEmpty
            ? normalizedProjectType(result.projectName, preservingUnknown: false)
            : normalizedProjectType(result.projectType)

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

    private static func normalizedLines(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{200b}", with: "")
            .components(separatedBy: "\n")
            .map(normalizedLine)
    }

    private static func normalizedLine(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // Copied job pages frequently preserve Markdown headings, block quotes,
        // and bold markers. Remove presentation-only syntax before matching.
        line = line.replacingOccurrences(
            of: #"^(?:>\s*)+"#,
            with: "",
            options: .regularExpression
        )
        line = line.replacingOccurrences(
            of: #"^#{1,6}\s*"#,
            with: "",
            options: .regularExpression
        )
        line = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
        line = line.replacingOccurrences(
            of: #"\s+#{1,6}$"#,
            with: "",
            options: .regularExpression
        )
        if line.count >= 2,
           (line.hasPrefix("`") && line.hasSuffix("`") ||
            line.hasPrefix("*") && line.hasSuffix("*")) {
            line.removeFirst()
            line.removeLast()
        }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let visible = metadataLines(from: lines)
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
                guard parts.count >= 2, looksLikePosition(parts[1]), looksLikeCompany(parts[0]) else { continue }
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
                if looksLikeCompany(candidate) { company = candidate }
            }
            if location.isEmpty, positionIndex + 1 < visible.count {
                let candidate = visible[positionIndex + 1]
                if looksLikeStandaloneLocation(candidate) { location = candidate }
            }
        }
        if location.isEmpty,
           let locationLine = visible.first(where: looksLikeStandaloneLocation) {
            location = locationLine
        }
        if location.isEmpty, !position.isEmpty,
           let titleLine = visible.first(where: { $0.contains(position) }),
           !matchedLocations(in: titleLine).isEmpty {
            location = titleLine
        }
        return (company, position, location)
    }

    private static func metadataLines(from lines: [String]) -> [String] {
        var metadata: [String] = []
        for line in lines where !line.isEmpty {
            if bodyHeadings.contains(where: { isHeading(line, named: $0) }) { break }
            metadata.append(line)
            if metadata.count == 16 { break }
        }
        return metadata
    }

    private static func inferredCompany(from lines: [String]) -> String {
        let contextMarkers = [
            "团队介绍", "公司介绍", "企业介绍", "关于我们", "欢迎加入", "加入我们",
            "团队主要", "公司主要"
        ]
        let contextLines = lines.filter { line in
            contextMarkers.contains(where: { line.localizedCaseInsensitiveContains($0) })
        }

        for line in contextLines {
            if let candidate = companyFollowingIntroductionMarker(in: line), !candidate.isEmpty {
                return candidate
            }
            if let legalName = legalCompanyName(in: line) { return legalName }
            if let known = knownCompany(in: line) { return known }
        }

        // Some sites put only a legal entity name near the title and omit a
        // “公司：” label. Keep this fallback close to the metadata block so a
        // company merely mentioned in the responsibilities is not selected.
        for line in metadataLines(from: lines) {
            if let legalName = legalCompanyName(in: line) { return legalName }
        }
        return ""
    }

    private static func companyFollowingIntroductionMarker(in line: String) -> String? {
        let markers = ["团队介绍", "公司介绍", "企业介绍", "关于我们"]
        guard let markerRange = markers.compactMap({ line.range(of: $0) }).min(by: {
            $0.lowerBound < $1.lowerBound
        }) else { return nil }

        var candidate = String(line[markerRange.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " :：-—|｜"))
        let boundaries = [
            "团队", "主要负责", "主要从事", "致力于", "成立于", "是一家", "是中国", "是全球",
            "，", "。", "；", ",", ";"
        ]
        if let boundary = boundaries.compactMap({ candidate.range(of: $0) }).min(by: {
            $0.lowerBound < $1.lowerBound
        }) {
            candidate = String(candidate[..<boundary.lowerBound])
        }
        if let known = knownCompany(in: candidate) { return known }
        candidate = stripDepartmentSuffix(from: cleanedValue(candidate))
        return looksLikeCompany(candidate) ? candidate : nil
    }

    private static func knownCompany(in value: String) -> String? {
        knownCompanyNames
            .sorted { $0.count > $1.count }
            .first { value.localizedCaseInsensitiveContains($0) }
    }

    private static func legalCompanyName(in value: String) -> String? {
        let pattern = #"([A-Za-z0-9\p{Han}·（）()]{2,50}?(?:股份有限公司|有限责任公司|有限公司|集团|银行|研究院))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        let candidate = cleanedValue(String(value[range]))
        return looksLikeCompany(candidate) ? candidate : nil
    }

    private static func stripDepartmentSuffix(from value: String) -> String {
        let suffixes = [
            "基础架构", "商业化", "生活服务", "大模型", "客户端", "服务端", "搜索", "推荐",
            "广告", "电商", "算法", "研发", "技术", "产品", "设计", "平台", "事业部"
        ]
        var result = value
        var removedSuffix = true
        while removedSuffix {
            removedSuffix = false
            if let suffix = suffixes.first(where: { result.hasSuffix($0) && result.count > $0.count + 1 }) {
                result.removeLast(suffix.count)
                removedSuffix = true
            }
        }
        return cleanedValue(result)
    }

    private static func inferredProject(from lines: [String]) -> (name: String, type: String) {
        let metadata = metadataLines(from: lines)
        let pattern = #"(?:20\d{2}\s*届)?[^，。；]{0,20}(?:校园招聘|秋季招聘|春季招聘|暑期实习|日常实习|提前批|秋招|春招|校招|补录|社会招聘|社招)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ("", "")
        }
        for line in metadata where line.count <= 60 {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard regex.firstMatch(in: line, range: range) != nil else { continue }
            if looksLikePosition(line), !line.contains("招聘"), !line.contains("届") { continue }
            return (cleanedValue(line), normalizedProjectType(line))
        }
        return ("", "")
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

    private static func normalizedProjectType(_ value: String, preservingUnknown: Bool = true) -> String {
        let source = value.lowercased()
        let mappings: [(String, [String])] = [
            ("提前批", ["提前批"]),
            ("暑期实习", ["暑期实习"]),
            ("日常实习", ["日常实习"]),
            ("秋招", ["秋招", "秋季招聘", "秋季校园招聘"]),
            ("春招", ["春招", "春季招聘", "春季校园招聘"]),
            ("补录", ["补录"]),
            ("社招", ["社招", "社会招聘"]),
            ("校招", ["校招", "校园招聘", "应届生招聘"])
        ]
        if let normalized = mappings.first(where: { mapping in
            mapping.1.contains(where: source.contains)
        })?.0 {
            return normalized
        }
        return preservingUnknown ? cleanedValue(value) : ""
    }

    private static func inferredCategory(from lines: [String]) -> String {
        let knownCategories = Set(["管培生", "算法", "数据", "产品", "设计", "测试", "运营", "市场", "销售", "职能", "研发"])
        for line in metadataLines(from: lines) where line.count <= 40 {
            guard !looksLikePosition(line), !looksLikeStandaloneLocation(line) else { continue }
            let category = normalizedCategory(explicit: line, position: "")
            if knownCategories.contains(category) { return category }
        }
        return ""
    }

    private static func normalizedCategory(explicit: String, position: String) -> String {
        let source = "\(explicit) \(position)".lowercased()
        let mappings: [(String, [String])] = [
            ("管培生", ["管培", "management trainee"]),
            ("算法", [
                "算法", "machine learning", "机器学习", "深度学习", "大模型", "llm", "vlm",
                "nlp", "自然语言处理", "aigc", "计算机视觉", "computer vision"
            ]),
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

    private static func looksLikeCompany(_ value: String) -> Bool {
        let candidate = cleanedValue(value)
        guard (2...50).contains(candidate.count) else { return false }
        if knownCompany(in: candidate) != nil { return true }
        if ["股份有限公司", "有限责任公司", "有限公司", "集团", "银行", "研究院"]
            .contains(where: { candidate.hasSuffix($0) }) { return true }

        let lowercased = candidate.lowercased()
        let rejectedTerms = [
            "校园招聘", "社会招聘", "校招", "社招", "秋招", "春招", "提前批", "实习",
            "职位", "岗位", "job id", "正式", "全职", "兼职", "研发 -", "研发-", "算法 -"
        ]
        guard !["我们", "本公司", "本团队", "该公司", "该团队"].contains(candidate),
              !rejectedTerms.contains(where: lowercased.contains),
              !looksLikePosition(candidate),
              !looksLikeStandaloneLocation(candidate),
              !bodyHeadings.contains(where: { isHeading(candidate, named: $0) }),
              !candidate.contains("："), !candidate.contains(":"),
              candidate.range(of: #"^20\d{2}\s*届"#, options: .regularExpression) == nil else {
            return false
        }
        return true
    }

    private static func looksLikeStandaloneLocation(_ value: String) -> Bool {
        let matches = matchedLocations(in: value)
        guard !matches.isEmpty, value.count <= 80 else { return false }
        var remainder = value.lowercased()
        for location in matches {
            remainder = remainder.replacingOccurrences(of: location.lowercased(), with: "")
        }
        let allowedWords = [
            "工作地点", "办公地点", "岗位地点", "工作城市", "办公城市", "base", "location",
            "正式", "全职", "实习", "可选", "任选", "多地", "市"
        ]
        for word in allowedWords {
            remainder = remainder.replacingOccurrences(of: word, with: "")
        }
        let separators = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "、,，/|｜·-—:：;；()（）[]【】")
        )
        return remainder.trimmingCharacters(in: separators).isEmpty
    }

    private static func matchedLocations(in value: String) -> [String] {
        knownLocations
            .compactMap { location -> (name: String, index: String.Index)? in
                guard let range = value.range(of: location, options: .caseInsensitive) else { return nil }
                return (location, range.lowerBound)
            }
            .sorted { $0.index < $1.index }
            .map(\.name)
    }

    private static func looksLikePosition(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return [
            "工程师", "经理", "实习生", "管培生", "顾问", "专员", "设计师", "分析师",
            "研究员", "科学家", "架构师", "developer", "engineer", "researcher", "scientist"
        ].contains(where: lowercased.contains)
    }

    private static func cleanedLocation(_ value: String) -> String {
        let cleaned = cleanedValue(value)
        let matched = matchedLocations(in: cleaned)
        return matched.isEmpty ? cleaned : matched.joined(separator: " / ")
    }

    private static func cleanedValue(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "|｜·,，;；")
        ))
    }
}
