import SwiftUI

enum ScheduleScope: String, CaseIterable, Identifiable {
    case upcoming = "即将到来"
    case past = "历史记录"
    case all = "全部"
    var id: String { rawValue }
}

enum ScheduleDisplayMode: String, CaseIterable, Identifiable {
    case list = "列表"
    case calendar = "月历"
    var id: String { rawValue }
}

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scope: ScheduleScope = .upcoming
    @State private var displayMode: ScheduleDisplayMode = .list
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedApplicationID: UUID?
    @State private var editingEvent: ProcessEvent?
    @State private var searchText = ""

    private var visibleEvents: [ProcessEvent] {
        store.events
            .filter { store.application(id: $0.applicationID)?.isArchived != true }
            .filter { event in
                switch scope {
                case .upcoming: return event.startsAt >= Date() && event.result.isPending
                case .past: return event.startsAt < Date() || !event.result.isPending
                case .all: return true
                }
            }
            .filter { event in
                guard !searchText.isEmpty else { return true }
                let application = store.application(id: event.applicationID)
                let company = application.flatMap { store.company(for: $0)?.name } ?? ""
                return event.title.localizedCaseInsensitiveContains(searchText)
                    || company.localizedCaseInsensitiveContains(searchText)
                    || (application?.position.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            .sorted { scope == .past ? $0.startsAt > $1.startsAt : $0.startsAt < $1.startsAt }
    }

    private var groupedEvents: [(Date, [ProcessEvent])] {
        let dictionary = Dictionary(grouping: visibleEvents) { Calendar.current.startOfDay(for: $0.startsAt) }
        return dictionary.map { ($0.key, $0.value) }.sorted { scope == .past ? $0.0 > $1.0 : $0.0 < $1.0 }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Picker("范围", selection: $scope) {
                        ForEach(ScheduleScope.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                    Picker("视图", selection: $displayMode) {
                        ForEach(ScheduleDisplayMode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    Spacer()
                    Text("\(visibleEvents.count) 项日程")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .padding(16)
                Divider()
                Group {
                    if displayMode == .calendar {
                        MonthCalendarView(month: $displayedMonth, events: visibleEvents) { event in
                            editingEvent = event
                        }
                    } else if visibleEvents.isEmpty {
                        EmptyStateView(icon: "calendar.badge.plus", title: "没有日程", message: "从右上角选择一个岗位并添加面试或笔试。")
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                ForEach(groupedEvents, id: \.0) { day, events in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(day, format: .dateTime.month().day().weekday(.wide))
                                            .font(.headline)
                                            .padding(.horizontal, 4)
                                        ForEach(events) { event in
                                            ScheduleEventCard(event: event) {
                                                editingEvent = event
                                            }
                                            .transition(
                                                .opacity
                                                    .combined(with: .scale(scale: 0.98))
                                                    .combined(with: .move(edge: .top))
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(20)
                            .frame(maxWidth: 820)
                            .frame(maxWidth: .infinity)
                            .animation(reduceMotion ? nil : AppMotion.standard, value: visibleEvents.map(\.id))
                        }
                    }
                }
                .id(displayMode)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
            }

            if editingEvent != nil || selectedApplicationID != nil {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeEditor)

                if let event = editingEvent {
                    EventEditorView(
                        applicationID: event.applicationID,
                        event: event,
                        onDismiss: closeEditor
                    )
                    .editorOverlayStyle()
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
                } else if let selectedApplicationID {
                    EventEditorView(applicationID: selectedApplicationID, onDismiss: closeEditor)
                        .editorOverlayStyle()
                        .transition(.scale(scale: 0.98).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("日程与面试")
        .onChange(of: displayMode) { _, mode in
            if mode == .calendar, scope == .upcoming { scope = .all }
        }
        .animation(reduceMotion ? nil : AppMotion.standard, value: displayMode)
        .animation(reduceMotion ? nil : AppMotion.standard, value: visibleEvents.count)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索日程")
        .toolbar {
            Menu {
                if store.activeApplications.isEmpty {
                    Text("请先新建投递")
                } else {
                    ForEach(store.activeApplications) { application in
                        Button("\(store.company(for: application)?.name ?? "未知公司") · \(application.position)") {
                            selectedApplicationID = application.id
                        }
                    }
                }
            } label: {
                Label("添加日程", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .animation(reduceMotion ? nil : AppMotion.quick, value: editingEvent?.id)
        .animation(reduceMotion ? nil : AppMotion.quick, value: selectedApplicationID)
    }

    private func closeEditor() {
        editingEvent = nil
        selectedApplicationID = nil
    }
}

private extension View {
    func editorOverlayStyle() -> some View {
        background(.background, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.24), radius: 24, y: 10)
    }
}

struct MonthCalendarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var month: Date
    let events: [ProcessEvent]
    let onEdit: (ProcessEvent) -> Void

    private let calendar = Calendar.current
    private let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    private var cells: [(Int, Date?)] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leading = (firstWeekday + 5) % 7
        var dates: [Date?] = Array(repeating: nil, count: leading)
        dates.append(contentsOf: range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstDay)
        })
        while dates.count % 7 != 0 { dates.append(nil) }
        return Array(dates.enumerated())
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                Button("今天") {
                    withAnimation(reduceMotion ? nil : AppMotion.standard) {
                        month = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
                    }
                }
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                Spacer()
                Text(month, format: .dateTime.year().month(.wide))
                    .font(.title2.bold())
                Spacer()
                Color.clear.frame(width: 100, height: 1)
            }
            .buttonStyle(.bordered)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(cells, id: \.0) { _, date in
                    if let date {
                        CalendarDayCell(date: date, events: eventsForDay(date), onEdit: onEdit)
                    } else {
                        Color.clear.frame(minHeight: 92)
                    }
                }
            }
            .id(month)
            .transition(.opacity)
        }
        .padding(20)
        .frame(maxWidth: 1_100, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    private func eventsForDay(_ date: Date) -> [ProcessEvent] {
        events.filter { calendar.isDate($0.startsAt, inSameDayAs: date) }.sorted { $0.startsAt < $1.startsAt }
    }

    private func changeMonth(_ offset: Int) {
        withAnimation(reduceMotion ? nil : AppMotion.standard) {
            month = calendar.date(byAdding: .month, value: offset, to: month) ?? month
        }
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let events: [ProcessEvent]
    let onEdit: (ProcessEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date, format: .dateTime.day())
                .font(.caption.weight(Calendar.current.isDateInToday(date) ? .bold : .regular))
                .foregroundStyle(Calendar.current.isDateInToday(date) ? .white : .primary)
                .frame(width: 23, height: 23)
                .background(Calendar.current.isDateInToday(date) ? Color.blue : Color.clear, in: Circle())
            ForEach(events.prefix(3)) { event in
                Button {
                    onEdit(event)
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(event.type.isInterview ? Color.purple : Color.blue)
                            .frame(width: 5, height: 5)
                        Text(event.startsAt, format: .dateTime.hour().minute())
                        Text(event.title).lineLimit(1)
                    }
                    .font(.caption2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(ResponsivePlainButtonStyle(pressedScale: 0.96))
            }
            if events.count > 3 {
                Text("还有 \(events.count - 3) 项")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(.quaternary) }
    }
}

struct ScheduleEventCard: View {
    @EnvironmentObject private var store: AppStore
    let event: ProcessEvent
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onEdit) {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(event.startsAt, format: .dateTime.hour().minute())
                            .font(.headline.monospacedDigit())
                        if let endsAt = event.endsAt {
                            Text(endsAt, format: .dateTime.hour().minute())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 58)
                    Rectangle()
                        .fill(event.type.isInterview ? Color.purple : Color.blue)
                        .frame(width: 4, height: 54)
                        .clipShape(Capsule())
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(event.title).fontWeight(.semibold)
                            Text(event.result.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let application = store.application(id: event.applicationID) {
                            Text("\(store.company(for: application)?.name ?? "未知公司") · \(application.position)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            Label(event.format.rawValue, systemImage: event.format == .online ? "video" : "mappin")
                            if !event.location.isEmpty { Text(event.location) }
                        }
                        .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsivePlainButtonStyle())
            if let url = URL(string: event.meetingURL), !event.meetingURL.isEmpty {
                Link(destination: url) {
                    Label("加入", systemImage: "video.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(.quaternary) }
        .interactiveCard(scale: 1.006, shadowOpacity: 0.08)
    }
}
