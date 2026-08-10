import Foundation

enum CSVService {
    static let headers = [
        "公司", "招聘项目", "岗位", "岗位类别", "部门", "工作地点", "JD链接", "投递渠道",
        "内推人", "投递时间", "当前状态", "自定义状态", "标签", "简历版本", "优先级", "薪资", "备注"
    ]

    @MainActor
    static func export(applications: [JobApplication], store: AppStore) -> Data {
        var rows = [headers]
        let formatter = ISO8601DateFormatter()
        for application in applications {
            rows.append([
                store.company(for: application)?.name ?? "",
                store.project(for: application)?.name ?? "",
                application.position,
                application.category,
                application.department,
                application.location,
                application.jdURL,
                application.channel,
                application.referrer,
                application.appliedAt.map { formatter.string(from: $0) } ?? "",
                application.status.rawValue,
                store.customStage(id: application.customStageID)?.name ?? "",
                store.tags(for: application).map(\.name).joined(separator: "|"),
                store.resumeVersion(for: application)?.name ?? "",
                application.priority.rawValue,
                application.salary,
                application.notes
            ])
        }
        let text = rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
        return Data(("\u{FEFF}" + text).utf8)
    }

    static func decode(_ data: Data) throws -> [ApplicationFormData] {
        guard data.count <= AppDataLimits.maximumCSVBytes else {
            throw CSVError.fileTooLarge
        }
        guard var text = String(data: data, encoding: .utf8) else {
            throw CSVError.invalidEncoding
        }
        text = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let rows = try parseRows(text)
        guard let first = rows.first else { return [] }
        guard rows.count - 1 <= AppDataLimits.maximumPrimaryRecords else {
            throw CSVError.tooManyRecords
        }
        var headerMap: [String: Int] = [:]
        for (index, header) in first.enumerated() {
            let normalizedHeader = header.trimmingCharacters(in: .whitespacesAndNewlines)
            if headerMap[normalizedHeader] == nil {
                headerMap[normalizedHeader] = index
            }
        }
        guard headerMap["公司"] != nil, headerMap["岗位"] != nil else {
            throw CSVError.missingRequiredColumns
        }
        let formatter = ISO8601DateFormatter()
        return rows.dropFirst().compactMap { row in
            func value(_ key: String) -> String {
                guard let index = headerMap[key], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let company = value("公司")
            let position = value("岗位")
            guard !company.isEmpty, !position.isEmpty else { return nil }
            var form = ApplicationFormData()
            form.companyName = company
            form.projectName = value("招聘项目")
            form.position = position
            form.category = value("岗位类别")
            form.department = value("部门")
            form.location = value("工作地点")
            form.jdURL = value("JD链接")
            form.channel = value("投递渠道").isEmpty ? "官网" : value("投递渠道")
            form.referrer = value("内推人")
            form.appliedAt = formatter.date(from: value("投递时间"))
            form.status = ApplicationStatus(rawValue: value("当前状态")) ?? .applied
            form.importedCustomStageName = value("自定义状态")
            form.importedTagNames = value("标签").split(separator: "|").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            form.importedResumeName = value("简历版本")
            form.priority = Priority(rawValue: value("优先级")) ?? .medium
            form.salary = value("薪资")
            form.notes = value("备注")
            return form
        }
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func parseRows(_ text: String) throws -> [[String]] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var index = normalizedText.startIndex

        while index < normalizedText.endIndex {
            let character = normalizedText[index]
            if character == "\"" {
                let next = normalizedText.index(after: index)
                if insideQuotes, next < normalizedText.endIndex, normalizedText[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    insideQuotes.toggle()
                }
            } else if character == ",", !insideQuotes {
                row.append(field)
                field = ""
            } else if character == "\n", !insideQuotes {
                row.append(field)
                if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = normalizedText.index(after: index)
        }
        guard !insideQuotes else { throw CSVError.malformedCSV }
        row.append(field)
        if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
        return rows
    }
}

enum CSVError: LocalizedError {
    case invalidEncoding
    case missingRequiredColumns
    case malformedCSV
    case fileTooLarge
    case tooManyRecords

    var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "CSV 文件不是 UTF-8 编码。"
        case .missingRequiredColumns: return "CSV 缺少“公司”或“岗位”列。"
        case .malformedCSV: return "CSV 中存在未闭合的引号。"
        case .fileTooLarge: return "CSV 文件过大，最大支持 25 MB。"
        case .tooManyRecords: return "CSV 记录超过允许的数量上限。"
        }
    }
}
