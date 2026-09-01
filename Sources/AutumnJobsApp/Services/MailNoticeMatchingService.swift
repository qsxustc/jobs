import Foundation

struct MailApplicationMatch: Equatable {
    let applicationID: UUID
    let score: Int
}

enum MailNoticeMatchingService {
    static func rankedApplicationMatches(
        for analysis: MailNoticeAnalysis,
        applications: [JobApplication],
        companies: [Company]
    ) -> [MailApplicationMatch] {
        let companyByID = Dictionary(uniqueKeysWithValues: companies.map { ($0.id, $0) })
        let source = canonicalText(analysis.sourceText)
        let primaryCompany = analysis.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedCompanies = (primaryCompany.isEmpty ? analysis.companyCandidates : [primaryCompany])
            .map(canonicalCompanyName)
            .filter { !$0.isEmpty }
        let parsedPosition = canonicalPositionName(analysis.position)

        return applications.compactMap { application in
            guard let company = companyByID[application.companyID] else { return nil }
            let companyName = canonicalCompanyName(company.name)
            let position = canonicalPositionName(application.position)
            var score = 0

            for parsedCompany in parsedCompanies {
                if companyName == parsedCompany {
                    score = max(score, 55)
                } else if companyName.count >= 2,
                          parsedCompany.count >= 2,
                          (companyName.contains(parsedCompany) || parsedCompany.contains(companyName)) {
                    score = max(score, 36)
                } else {
                    let similarity = textSimilarity(companyName, parsedCompany)
                    if similarity >= 0.55 {
                        score = max(score, Int((similarity * 30).rounded()))
                    }
                }
            }

            if companyName.count >= 2, source.contains(companyName) {
                score += 22
            }

            if !parsedPosition.isEmpty {
                if position == parsedPosition {
                    score += 30
                } else if position.count >= 2,
                          parsedPosition.count >= 2,
                          (position.contains(parsedPosition) || parsedPosition.contains(position)) {
                    score += 18
                } else {
                    let similarity = textSimilarity(position, parsedPosition)
                    if similarity >= 0.55 {
                        score += Int((similarity * 16).rounded())
                    }
                }
            }

            if position.count >= 3, source.contains(position) {
                score += 12
            }

            guard score > 0 else { return nil }
            return MailApplicationMatch(applicationID: application.id, score: score)
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.applicationID.uuidString < $1.applicationID.uuidString
        }
    }

    static func automaticApplicationID(from matches: [MailApplicationMatch]) -> UUID? {
        guard let best = matches.first, best.score >= 50 else { return nil }
        if matches.count > 1, best.score - matches[1].score < 8 { return nil }
        return best.applicationID
    }

    static func suggestedCompanyNames(
        for analysis: MailNoticeAnalysis,
        companies: [Company],
        query: String,
        limit: Int = 5
    ) -> [String] {
        guard limit > 0 else { return [] }
        let normalizedQuery = canonicalCompanyName(query)
        let source = canonicalText(analysis.sourceText)
        let parsedNames = ([analysis.companyName] + analysis.companyCandidates)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let parsedCanonicalNames = parsedNames.map(canonicalCompanyName).filter { !$0.isEmpty }
        var scored: [(name: String, canonical: String, score: Int, isExisting: Bool)] = []

        for company in companies {
            let canonical = canonicalCompanyName(company.name)
            guard !canonical.isEmpty else { continue }
            var score = 0

            if !normalizedQuery.isEmpty {
                if canonical == normalizedQuery {
                    score = 150
                } else if canonical.contains(normalizedQuery) || normalizedQuery.contains(canonical) {
                    score = 115
                } else {
                    let similarity = textSimilarity(canonical, normalizedQuery)
                    if similarity >= 0.4 { score = Int((similarity * 90).rounded()) }
                }
            }

            for parsed in parsedCanonicalNames {
                if canonical == parsed {
                    score = max(score, 140)
                } else if canonical.count >= 2,
                          parsed.count >= 2,
                          (canonical.contains(parsed) || parsed.contains(canonical)) {
                    score = max(score, 100)
                } else {
                    let similarity = textSimilarity(canonical, parsed)
                    if similarity >= 0.5 {
                        score = max(score, Int((similarity * 80).rounded()))
                    }
                }
            }

            if canonical.count >= 2, source.contains(canonical) {
                score = max(score, 90)
            }
            if score > 0 {
                scored.append((company.name, canonical, score, true))
            }
        }

        for (index, name) in parsedNames.enumerated() {
            let canonical = canonicalCompanyName(name)
            guard !canonical.isEmpty else { continue }
            if !normalizedQuery.isEmpty {
                let similarity = textSimilarity(canonical, normalizedQuery)
                guard canonical.contains(normalizedQuery) || normalizedQuery.contains(canonical) || similarity >= 0.4 else {
                    continue
                }
            }
            scored.append((name, canonical, 120 - min(index, 20), false))
        }

        let sorted = scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.isExisting != $1.isExisting { return $0.isExisting }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        var seen: Set<String> = []
        var results: [String] = []
        for item in sorted where !seen.contains(item.canonical) {
            seen.insert(item.canonical)
            results.append(item.name)
            if results.count == limit { break }
        }
        return results
    }

    private static func canonicalCompanyName(_ value: String) -> String {
        let withoutParenthetical = value.replacingOccurrences(
            of: #"[(（][^)）]*[)）]"#,
            with: "",
            options: .regularExpression
        )
        var normalized = canonicalText(withoutParenthetical)
        var removedSuffix = true
        while removedSuffix {
            removedSuffix = false
            for suffix in ["股份有限公司", "有限责任公司", "有限公司", "集团", "公司"] {
                if normalized.hasSuffix(suffix), normalized.count > suffix.count {
                    normalized.removeLast(suffix.count)
                    removedSuffix = true
                    break
                }
            }
        }
        return normalized
    }

    private static func canonicalPositionName(_ value: String) -> String {
        var normalized = canonicalText(value)
        for suffix in ["岗位", "职位"] where normalized.hasSuffix(suffix) && normalized.count > suffix.count {
            normalized.removeLast(suffix.count)
            break
        }
        return normalized.replacingOccurrences(of: "研发", with: "开发")
    }

    private static func canonicalText(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func textSimilarity(_ left: String, _ right: String) -> Double {
        if left == right { return 1 }
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left.count == 1 || right.count == 1 { return 0 }
        let leftPairs = Set(zip(left, left.dropFirst()).map { String([$0, $1]) })
        let rightPairs = Set(zip(right, right.dropFirst()).map { String([$0, $1]) })
        guard !leftPairs.isEmpty, !rightPairs.isEmpty else { return 0 }
        return Double(leftPairs.intersection(rightPairs).count * 2) /
            Double(leftPairs.count + rightPairs.count)
    }
}
