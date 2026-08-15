import SwiftUI
import Charts

private struct StageCount: Identifiable {
    let id: String
    let name: String
    let count: Int
    let color: Color
}

private struct ChannelCount: Identifiable {
    let channel: String
    let count: Int
    var id: String { channel }
}

private struct WeekCount: Identifiable {
    let week: Date
    let count: Int
    var id: Date { week }
}

private struct ResumePerformance: Identifiable {
    let resume: ResumeVersion
    let applications: Int
    let interviews: Int
    let offers: Int
    var id: UUID { resume.id }
}

struct AnalyticsView: View {
    @EnvironmentObject private var store: AppStore

    private var total: Int { store.activeApplications.count }
    private var applied: [JobApplication] { store.activeApplications.filter(store.isSubmitted) }
    private var responded: [JobApplication] {
        applied.filter(store.hasResponse)
    }
    private var interviewedIDs: Set<UUID> {
        let appliedIDs = Set(applied.map(\.id))
        return Set(store.events
            .filter { $0.type.isInterview && $0.result != .cancelled && appliedIDs.contains($0.applicationID) }
            .map(\.applicationID))
    }
    private var offerCount: Int {
        store.applicationCount(in: .offer)
    }

    private var stageCounts: [StageCount] {
        ApplicationAnalysisCategory.allCases.compactMap { category -> StageCount? in
            let count = store.applicationCount(in: category)
            return count == 0 ? nil : StageCount(
                id: category.id,
                name: category.rawValue,
                count: count,
                color: category.color
            )
        }
    }

    private var channelCounts: [ChannelCount] {
        Dictionary(grouping: applied) { $0.channel.isEmpty ? "未填写" : $0.channel }
            .map { ChannelCount(channel: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private var categoryCounts: [ChannelCount] {
        Dictionary(grouping: applied) { $0.category.isEmpty ? "未填写" : $0.category }
            .map { ChannelCount(channel: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private var locationCounts: [ChannelCount] {
        Dictionary(grouping: applied) { $0.location.isEmpty ? "未填写" : $0.location }
            .map { ChannelCount(channel: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private var resumePerformance: [ResumePerformance] {
        store.resumeVersions.map { resume in
            let resumeApplications = applied.filter { $0.resumeVersionID == resume.id }
            return ResumePerformance(
                resume: resume,
                applications: resumeApplications.count,
                interviews: resumeApplications.filter { interviewedIDs.contains($0.id) }.count,
                offers: resumeApplications.filter { store.analysisCategory(for: $0) == .offer }.count
            )
        }
        .filter { $0.applications > 0 }
        .sorted { $0.applications > $1.applications }
    }

    private var weeklyCounts: [WeekCount] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: applied.compactMap(\.appliedAt)) { date in
            calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        }
        return grouped.map { WeekCount(week: $0.key, count: $0.value.count) }.sorted { $0.week < $1.week }
    }

    private var averageResponseDays: Double? {
        let durations: [Double] = responded.compactMap { application in
            guard let appliedAt = application.appliedAt else { return nil }
            guard let responseDate = store.firstResponseDate(for: application) else { return nil }
            return max(0, responseDate.timeIntervalSince(appliedAt) / 86_400)
        }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    MetricCard(title: "已投递", value: "\(applied.count)", subtitle: "机会总量", icon: "paperplane.fill", color: .blue)
                    MetricCard(title: "回复率", value: percent(responded.count, of: applied.count), subtitle: "\(responded.count) 个流程有反馈", icon: "envelope.open.fill", color: .cyan)
                    MetricCard(title: "面试率", value: percent(interviewedIDs.count, of: applied.count), subtitle: "\(interviewedIDs.count) 个岗位获得面试", icon: "person.2.fill", color: .purple)
                    MetricCard(title: "Offer 率", value: percent(offerCount, of: applied.count), subtitle: "\(offerCount) 个 Offer", icon: "trophy.fill", color: .green)
                }

                HStack(alignment: .top, spacing: 18) {
                    SectionCard("投递趋势", subtitle: "按周统计的投递数量") {
                        if weeklyCounts.isEmpty {
                            EmptyStateView(icon: "chart.xyaxis.line", title: "暂无趋势", message: "记录投递时间后生成趋势。")
                        } else {
                            Chart(weeklyCounts) { item in
                                LineMark(x: .value("周", item.week), y: .value("投递", item.count))
                                    .foregroundStyle(.blue)
                                    .interpolationMethod(.catmullRom)
                                PointMark(x: .value("周", item.week), y: .value("投递", item.count))
                                    .foregroundStyle(.blue)
                            }
                            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                            .frame(height: 250)
                        }
                    }
                    SectionCard("状态分布", subtitle: "按统一分析分类统计当前机会") {
                        if stageCounts.isEmpty {
                            EmptyStateView(icon: "chart.bar", title: "暂无数据", message: "新建投递后生成状态分布。")
                        } else {
                            Chart(stageCounts) { item in
                                BarMark(x: .value("数量", item.count), y: .value("状态", item.name))
                                    .foregroundStyle(item.color.gradient)
                                    .cornerRadius(4)
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 250)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    dimensionChart("岗位类别", subtitle: "投递主要集中在哪些方向", values: categoryCounts, color: .indigo)
                    dimensionChart("工作城市", subtitle: "不同城市的机会数量", values: locationCounts, color: .teal)
                }

                SectionCard("简历版本效果", subtitle: "比较不同简历带来的面试和 Offer 转化") {
                    if resumePerformance.isEmpty {
                        EmptyStateView(icon: "doc.text.magnifyingglass", title: "暂无关联数据", message: "在投递记录中选择所使用的简历版本。")
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                            GridRow {
                                Text("简历版本").foregroundStyle(.secondary)
                                Text("投递").foregroundStyle(.secondary)
                                Text("面试").foregroundStyle(.secondary)
                                Text("面试率").foregroundStyle(.secondary)
                                Text("Offer").foregroundStyle(.secondary)
                            }
                            Divider().gridCellColumns(5)
                            ForEach(resumePerformance) { item in
                                GridRow {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.resume.name).fontWeight(.medium)
                                        Text(item.resume.target).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text("\(item.applications)")
                                    Text("\(item.interviews)")
                                    Text(percent(item.interviews, of: item.applications)).foregroundStyle(.purple)
                                    Text("\(item.offers)").foregroundStyle(.green)
                                }
                                Divider().gridCellColumns(5)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    SectionCard("投递渠道", subtitle: "不同来源的机会数量") {
                        if channelCounts.isEmpty {
                            EmptyStateView(icon: "arrow.triangle.branch", title: "暂无渠道数据", message: "在投递记录中填写渠道。")
                        } else {
                            Chart(channelCounts) { item in
                                SectorMark(
                                    angle: .value("数量", item.count),
                                    innerRadius: .ratio(0.58),
                                    angularInset: 2
                                )
                                .foregroundStyle(by: .value("渠道", item.channel))
                            }
                            .chartLegend(position: .bottom, spacing: 10)
                            .frame(height: 260)
                        }
                    }
                    SectionCard("流程效率", subtitle: "帮助发现跟进节奏") {
                        VStack(spacing: 16) {
                            efficiencyRow("平均首次响应", averageResponseDays.map { String(format: "%.1f 天", $0) } ?? "数据不足", icon: "clock.arrow.circlepath")
                            Divider()
                            efficiencyRow("已记录面试", "\(store.events.filter { $0.type.isInterview && $0.result != .cancelled && store.application(id: $0.applicationID)?.isArchived == false }.count) 场", icon: "person.crop.rectangle.stack")
                            Divider()
                            efficiencyRow("未来 7 天日程", "\(upcomingSevenDaysCount) 项", icon: "calendar.badge.clock")
                            Divider()
                            efficiencyRow("逾期待办", "\(overdueTodoCount) 项", icon: "exclamationmark.circle")
                        }
                        .frame(height: 260, alignment: .top)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("数据分析")
    }

    private var upcomingSevenDaysCount: Int {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return store.upcomingEvents.filter { $0.startsAt <= end }.count
    }

    private var overdueTodoCount: Int {
        store.openTodos.filter { ($0.dueAt ?? .distantFuture) < Date() }.count
    }

    private func percent(_ numerator: Int, of denominator: Int) -> String {
        guard denominator > 0 else { return "0%" }
        return "\(Int((Double(numerator) / Double(denominator) * 100).rounded()))%"
    }

    private func efficiencyRow(_ title: String, _ value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 28)
            Text(title)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }

    private func dimensionChart(_ title: String, subtitle: String, values: [ChannelCount], color: Color) -> some View {
        SectionCard(title, subtitle: subtitle) {
            if values.isEmpty {
                EmptyStateView(icon: "chart.bar", title: "暂无数据", message: "完善投递信息后生成分析。")
            } else {
                Chart(values.prefix(8)) { item in
                    BarMark(
                        x: .value("类别", item.channel),
                        y: .value("数量", item.count)
                    )
                    .foregroundStyle(color.gradient)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text("\(item.count)").font(.caption2)
                    }
                }
                .frame(height: 240)
            }
        }
    }
}
