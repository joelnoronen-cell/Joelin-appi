import SwiftData
import SwiftUI

struct WeekView: View {
    @Environment(JarvisStore.self) private var store
    @Query(sort: \Plan.start, animation: .smooth) private var plans: [Plan]

    @State private var anchor = Date.now
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var slideEdge: Edge = .trailing

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { timeline in
                content(now: timeline.date)
            }
            .background { AuroraBackground() }
            .navigationTitle("Week")
        }
    }

    private func content(now: Date) -> some View {
        let calendar = Calendar.current
        let week = store.week(containing: anchor, plans: plans)
        let selected = week.first { calendar.isDate($0.day, inSameDayAs: selectedDay) }
            ?? DayAgenda(day: selectedDay, items: store.agenda(on: selectedDay, plans: plans))
        let weekKey = calendar.startOfWeek(for: anchor)
        let isCurrentWeek = calendar.isDate(weekKey, inSameDayAs: calendar.startOfWeek(for: now))

        return ScrollView {
            VStack(spacing: 18) {
                WeekHeader(
                    days: week.map(\.day),
                    now: now,
                    onPrevious: { changeWeek(by: -1) },
                    onNext: { changeWeek(by: 1) }
                )

                DayStrip(
                    week: week,
                    weekKey: weekKey,
                    slideEdge: slideEdge,
                    selection: $selectedDay,
                    onSwipe: { changeWeek(by: $0) }
                )

                WeekPulseCard(
                    week: week,
                    selection: $selectedDay,
                    isSpeaking: store.voice.isSpeaking,
                    onBrief: { brief(week: week, now: now) }
                )

                DaySection(
                    agenda: selected,
                    now: now,
                    onAdd: { store.route = .newPlan(Agenda.suggestedStart(on: selected.day, now: now)) },
                    onAsk: { store.route = .ask }
                )
                .id(selected.day)
                .transition(.blurReplace)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .toolbar {
            if !isCurrentWeek || !calendar.isDate(selectedDay, inSameDayAs: now) {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") {
                        jumpToToday(now: now)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.route = .newPlan(Agenda.suggestedStart(on: selectedDay, now: now))
                } label: {
                    Label("Add Plan", systemImage: "plus")
                }
            }
        }
    }

    private func changeWeek(by delta: Int) {
        let calendar = Calendar.current
        slideEdge = delta > 0 ? .trailing : .leading
        withAnimation(.smooth(duration: 0.45)) {
            anchor = calendar.date(byAdding: .weekOfYear, value: delta, to: anchor) ?? anchor
            selectedDay = calendar.date(byAdding: .weekOfYear, value: delta, to: selectedDay) ?? selectedDay
        }
    }

    private func jumpToToday(now: Date) {
        let calendar = Calendar.current
        slideEdge = anchor > now ? .leading : .trailing
        withAnimation(.smooth(duration: 0.45)) {
            anchor = now
            selectedDay = calendar.startOfDay(for: now)
        }
    }

    private func brief(week: [DayAgenda], now: Date) {
        if store.voice.isSpeaking {
            store.voice.stop()
        } else {
            store.voice.speak(Briefing.week(week, now: now))
        }
    }
}

// MARK: - Header

private struct WeekHeader: View {
    let days: [Date]
    let now: Date
    var onPrevious: () -> Void
    var onNext: () -> Void

    private var title: String {
        guard let first = days.first, let last = days.last else { return "" }
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }

    private var subtitle: String {
        guard let first = days.first else { return "" }
        let calendar = Calendar.current
        let thisWeek = calendar.startOfWeek(for: now)
        let offset = calendar.dateComponents([.weekOfYear], from: thisWeek, to: first).weekOfYear ?? 0
        switch offset {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        default: return "Week \(calendar.component(.weekOfYear, from: first))"
        }
    }

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Previous week")

            Spacer()

            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontDesign(.rounded)
                Text(subtitle.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
            }
            .id(title)
            .transition(.blurReplace)

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Next week")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}

// MARK: - Day strip

/// Seven glass day pills. The selection is a glowing capsule that glides
/// between days; swipe sideways to change week.
private struct DayStrip: View {
    let week: [DayAgenda]
    let weekKey: Date
    let slideEdge: Edge
    @Binding var selection: Date
    var onSwipe: (Int) -> Void

    @Namespace private var namespace

    var body: some View {
        let calendar = Calendar.current

        ZStack {
            HStack(spacing: 4) {
                ForEach(week) { entry in
                    let isSelected = calendar.isDate(entry.day, inSameDayAs: selection)
                    let isToday = calendar.isDateInToday(entry.day)
                    Button {
                        withAnimation(.snappy(duration: 0.35)) {
                            selection = entry.day
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text(entry.day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                            Text(entry.day.formatted(.dateTime.day()))
                                .font(.title3.weight(.bold))
                                .fontDesign(.rounded)
                                .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                            LoadDots(count: entry.items.count, highlighted: isSelected)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [JarvisTheme.cyan, JarvisTheme.blue],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .shadow(color: JarvisTheme.blue.opacity(0.5), radius: 10, y: 4)
                                    .matchedGeometryEffect(id: weekKey, in: namespace)
                            } else if isToday {
                                Capsule()
                                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                            }
                        }
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.day.formatted(.dateTime.weekday(.wide).month().day()))
                    .accessibilityValue(Fmt.count(entry.items.count, "plan"))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .id(weekKey)
            .transition(.push(from: slideEdge))
        }
        .clipShape(.rect(cornerRadius: 24))
        .padding(6)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .sensoryFeedback(.selection, trigger: selection)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > 50, abs(dx) > abs(value.translation.height) else { return }
                    onSwipe(dx < 0 ? 1 : -1)
                }
        )
    }
}

private struct LoadDots: View {
    let count: Int
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(count, 4), id: \.self) { _ in
                Circle()
                    .frame(width: 4, height: 4)
            }
        }
        .frame(height: 4)
        .foregroundStyle(highlighted ? Color.white : Color.accentColor)
    }
}

// MARK: - Week pulse

/// Bar chart of how loaded each day is, with the done share highlighted.
private struct WeekPulseCard: View {
    let week: [DayAgenda]
    @Binding var selection: Date
    let isSpeaking: Bool
    var onBrief: () -> Void

    @State private var grown = false

    var body: some View {
        let calendar = Calendar.current
        let maxCount = max(week.map(\.items.count).max() ?? 0, 4)
        let total = week.reduce(0) { $0 + $1.items.count }
        let done = week.reduce(0) { $0 + $1.doneCount }

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEEK PULSE")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    Text("\(Fmt.count(total, "plan")) · \(done) done")
                        .font(.headline)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button(action: onBrief) {
                    Image(systemName: isSpeaking ? "stop.fill" : "waveform")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(isSpeaking ? "Stop" : "Brief me on this week")
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(week) { entry in
                    let isSelected = calendar.isDate(entry.day, inSameDayAs: selection)
                    let ratio = Double(entry.items.count) / Double(maxCount)
                    let doneRatio = Double(entry.doneCount) / Double(maxCount)
                    VStack(spacing: 8) {
                        GeometryReader { proxy in
                            ZStack(alignment: .bottom) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.07))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [JarvisTheme.cyan, JarvisTheme.blue],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .opacity(isSelected ? 1 : 0.45)
                                    .frame(height: grown && entry.items.count > 0 ? max(proxy.size.height * ratio, 8) : 0)
                                Capsule()
                                    .fill(JarvisTheme.violet.opacity(0.85))
                                    .frame(height: grown && entry.doneCount > 0 ? max(proxy.size.height * doneRatio, 6) : 0)
                            }
                        }
                        Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.35)) {
                            selection = entry.day
                        }
                    }
                }
            }
            .frame(height: 110)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: week.map(\.items.count))

            HStack(spacing: 14) {
                legend(color: JarvisTheme.blue, title: "Planned")
                legend(color: JarvisTheme.violet, title: "Done")
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.15)) {
                grown = true
            }
        }
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Day section

private struct DaySection: View {
    let agenda: DayAgenda
    let now: Date
    var onAdd: () -> Void
    var onAsk: () -> Void

    var body: some View {
        let calendar = Calendar.current
        let isToday = calendar.isDate(agenda.day, inSameDayAs: now)
        let timed = agenda.items.filter { !$0.isAnytime }
        let anytime = agenda.items.filter(\.isAnytime)

        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "Today" : agenda.day.formatted(.dateTime.weekday(.wide)))
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                    Text(agenda.day.formatted(.dateTime.month(.wide).day()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !agenda.items.isEmpty {
                    Text(Fmt.count(agenda.items.count, "plan"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                }
            }
            .padding(.horizontal, 4)

            if agenda.items.isEmpty {
                EmptyStateCard(
                    title: "A free day",
                    message: "Nothing planned yet. Enjoy the breathing room — or let Jarvis fill it.",
                    onAsk: onAsk,
                    onAdd: onAdd
                )
            }

            if !timed.isEmpty {
                AgendaTimeline(items: timed, now: now, showsNowMarker: isToday)
            }

            if !anytime.isEmpty {
                SectionHeader(title: "Anytime", detail: "\(anytime.count)")
                VStack(spacing: 10) {
                    ForEach(anytime) { item in
                        AgendaCard(item: item)
                    }
                }
            }
        }
    }
}
