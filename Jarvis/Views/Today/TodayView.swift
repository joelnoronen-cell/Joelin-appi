import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(JarvisStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.start, animation: .smooth) private var plans: [Plan]
    @AppStorage(SettingsKey.userName) private var userName = ""

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { timeline in
                content(now: timeline.date)
            }
            .background { AuroraBackground() }
        }
    }

    private func content(now: Date) -> some View {
        let items = store.agenda(on: now, plans: plans)
        let timed = items.filter { !$0.isAnytime }
        let anytime = items.filter(\.isAnytime)
        let briefing = Briefing.today(items, now: now)

        return ScrollView {
            VStack(spacing: 20) {
                TodayHeader(
                    now: now,
                    name: userName,
                    isSpeaking: store.voice.isSpeaking,
                    onOrbTap: { speakBriefing(briefing, now: now) }
                )

                BriefingCard(
                    text: briefing,
                    isSpeaking: store.voice.isSpeaking,
                    onSpeak: { speakBriefing(briefing, now: now) },
                    onAsk: { store.route = .ask }
                )

                DayStatsStrip(items: items, now: now)

                if let focus = Agenda.focus(in: items, now: now) {
                    FocusCard(item: focus, now: now)
                        .transition(.blurReplace)
                }

                if items.isEmpty {
                    EmptyStateCard(
                        title: "Nothing on the radar",
                        message: "Tell Jarvis what's coming up — “Gym at 6pm”, “Dentist Friday 3pm” — and it shows up here.",
                        showsSample: plans.isEmpty,
                        onAsk: { store.route = .ask },
                        onAdd: { store.route = .newPlan(Agenda.suggestedStart(on: now, now: now)) },
                        onSample: { withAnimation(.smooth) { SampleData.load(into: context) } }
                    )
                }

                if !timed.isEmpty {
                    SectionHeader(title: "Schedule", detail: "\(timed.filter(\.isDone).count)/\(timed.count) done")
                    AgendaTimeline(items: timed, now: now)
                }

                if !anytime.isEmpty {
                    SectionHeader(title: "Anytime today", detail: "\(anytime.count)")
                    VStack(spacing: 10) {
                        ForEach(anytime) { item in
                            AgendaCard(item: item)
                                .transition(.scale(scale: 0.94).combined(with: .opacity))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .animation(.smooth, value: items.map(\.id))
        }
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.route = .newPlan(Agenda.suggestedStart(on: now, now: now))
                } label: {
                    Label("Add Plan", systemImage: "plus")
                }
            }
        }
    }

    private func speakBriefing(_ briefing: String, now: Date) {
        if store.voice.isSpeaking {
            store.voice.stop()
        } else {
            store.voice.speak("\(Briefing.greeting(at: now, name: userName)). \(briefing)")
        }
    }
}

// MARK: - Header

private struct TodayHeader: View {
    let now: Date
    let name: String
    let isSpeaking: Bool
    var onOrbTap: () -> Void

    private let orbSize: CGFloat = 104

    var body: some View {
        VStack(spacing: 18) {
            Button(action: onOrbTap) {
                JarvisOrb(size: orbSize, isActive: isSpeaking)
            }
            .buttonStyle(.plain)
            .padding(.vertical, orbSize * 0.24)
            .accessibilityLabel(isSpeaking ? "Stop briefing" : "Hear your briefing")

            VStack(spacing: 6) {
                Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(2.4)
                    .foregroundStyle(.secondary)
                Text(Briefing.greeting(at: now, name: name))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

// MARK: - Briefing

private struct BriefingCard: View {
    let text: String
    let isSpeaking: Bool
    var onSpeak: () -> Void
    var onAsk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("JARVIS BRIEFING", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: onSpeak) {
                            Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 20, height: 20)
                        }
                        .accessibilityLabel(isSpeaking ? "Stop" : "Read aloud")
                        Button(action: onAsk) {
                            Image(systemName: "text.bubble.fill")
                                .frame(width: 20, height: 20)
                        }
                        .accessibilityLabel("Ask Jarvis")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                }
            }
            TypewriterText(text: text)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

// MARK: - Stats

private struct DayStatsStrip: View {
    let items: [AgendaItem]
    let now: Date

    var body: some View {
        let done = items.filter(\.isDone).count
        let progress = items.isEmpty ? 0 : Double(done) / Double(items.count)
        let planned = items.filter { !$0.isAnytime }.reduce(0) { $0 + $1.durationMinutes }
        let free = Briefing.freeSlots(on: now, items: items, now: now)
            .reduce(0) { $0 + Int($1.duration / 60) }

        HStack(spacing: 10) {
            StatTile(label: "Progress", value: "\(done)/\(items.count)") {
                ProgressRing(progress: progress, lineWidth: 5)
                    .frame(width: 26, height: 26)
            }
            StatTile(label: "Planned", value: Fmt.duration(planned)) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(JarvisTheme.blue)
            }
            StatTile(label: "Free left", value: Fmt.duration(free)) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(Color(hex: 0x2FD69A))
            }
        }
    }
}

private struct StatTile<Icon: View>: View {
    let label: String
    let value: String
    @ViewBuilder var icon: Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            icon
                .font(.title3)
                .frame(height: 26)
            Text(value)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

// MARK: - Focus

/// Hero card for whatever is happening now, or what's next.
private struct FocusCard: View {
    let item: AgendaItem
    let now: Date

    private var isCurrent: Bool { item.start <= now && item.end > now }

    private var progress: Double {
        let total = item.end.timeIntervalSince(item.start)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(item.start) / total, 0), 1)
    }

    private var countdown: String {
        if isCurrent {
            let minutes = max(Int(item.end.timeIntervalSince(now) / 60), 0)
            return "\(Fmt.duration(minutes)) left"
        }
        let minutes = max(Int(item.start.timeIntervalSince(now) / 60), 0)
        return minutes == 0 ? "starting now" : "in \(Fmt.duration(minutes))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(isCurrent ? "HAPPENING NOW" : "UP NEXT", systemImage: isCurrent ? "dot.radiowaves.left.and.right" : "arrow.forward.circle.fill")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(item.tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isCurrent)
                Spacer()
                Text(countdown)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                Text("\(Fmt.time(item.start)) – \(Fmt.time(item.end))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if isCurrent {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule()
                            .fill(item.tint.gradient)
                            .frame(width: max(proxy.size.width * progress, 6))
                    }
                }
                .frame(height: 6)
                .animation(.smooth, value: progress)
            }

            if let plan = item.plan {
                Button {
                    PlanActions.toggleDone(plan)
                } label: {
                    Label("Mark Done", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(item.tint)
            }
        }
        .padding(20)
        .glassEffect(.regular.tint(item.tint.opacity(0.22)).interactive(), in: .rect(cornerRadius: 30))
    }
}

#Preview {
    RootView()
        .modelContainer(for: Plan.self, inMemory: true)
}
