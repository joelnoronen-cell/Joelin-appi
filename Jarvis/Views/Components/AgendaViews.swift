import SwiftData
import SwiftUI

/// A single plan or event on a Liquid Glass card. Tapping a plan opens the
/// editor; long-press for quick actions.
struct AgendaCard: View {
    let item: AgendaItem

    @Environment(JarvisStore.self) private var store
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 38, height: 38)
                .background(item.tint.opacity(0.18), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(item.isDone, color: .secondary)
                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                    .lineLimit(2)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if item.isImportant && !item.isDone {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.scale.combined(with: .opacity))
            }

            if let plan = item.plan {
                CompletionButton(plan: plan)
            } else {
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(item.tint.opacity(item.isDone ? 0.04 : 0.14)).interactive(), in: .rect(cornerRadius: 22))
        .opacity(item.isDone ? 0.72 : 1)
        .contentShape(.rect(cornerRadius: 22))
        .onTapGesture {
            if let plan = item.plan {
                store.route = .edit(plan)
            }
        }
        .contextMenu {
            if let plan = item.plan {
                Button {
                    store.route = .edit(plan)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    PlanActions.toggleDone(plan)
                } label: {
                    Label(plan.isDone ? "Mark as Not Done" : "Mark as Done", systemImage: "checkmark.circle")
                }
                Button {
                    PlanActions.moveToTomorrow(plan)
                } label: {
                    Label("Move to Tomorrow", systemImage: "arrow.turn.down.right")
                }
                Button {
                    PlanActions.duplicate(plan, in: context)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Divider()
                Button(role: .destructive) {
                    PlanActions.delete(plan, in: context)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

/// Animated check circle with haptics.
struct CompletionButton: View {
    let plan: Plan

    var body: some View {
        Button {
            PlanActions.toggleDone(plan)
        } label: {
            Image(systemName: plan.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(plan.isDone ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: plan.isDone)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: plan.isDone) { _, isDone in isDone }
        .accessibilityLabel(plan.isDone ? "Mark as not done" : "Mark as done")
    }
}

/// Today/day timeline: time column, a glowing rail and glass cards, with a
/// live "now" marker slotted between past and upcoming items.
struct AgendaTimeline: View {
    let items: [AgendaItem]
    let now: Date
    var showsNowMarker: Bool = true

    @State private var appeared = false

    private static let timeColumn: CGFloat = 64
    private static let railColumn: CGFloat = 14

    private enum Entry: Identifiable {
        case item(AgendaItem)
        case now(Date)

        var id: String {
            switch self {
            case .item(let item): item.id
            case .now: "now-marker"
            }
        }
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        var placed = !showsNowMarker
        for item in items {
            if !placed && item.start > now {
                result.append(.now(now))
                placed = true
            }
            result.append(.item(item))
        }
        if !placed {
            result.append(.now(now))
        }
        return result
    }

    var body: some View {
        let allEntries = entries
        VStack(spacing: 10) {
            ForEach(Array(allEntries.enumerated()), id: \.element.id) { index, entry in
                Group {
                    switch entry {
                    case .item(let item):
                        row(for: item)
                    case .now(let date):
                        NowMarker(date: date, timeColumn: Self.timeColumn, railColumn: Self.railColumn)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 26)
                .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(Double(index) * 0.05), value: appeared)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    )
                )
            }
        }
        .background(alignment: .topLeading) {
            // Continuous rail behind the dots.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.secondary.opacity(0), Color.secondary.opacity(0.35), Color.secondary.opacity(0.35), Color.secondary.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .padding(.leading, Self.timeColumn + 12 + Self.railColumn / 2 - 1)
        }
        .onAppear {
            appeared = true
        }
    }

    private func row(for item: AgendaItem) -> some View {
        let isCurrent = !item.isDone && item.start <= now && item.end > now
        let isPast = item.end <= now
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.isAnytime ? "All day" : Fmt.time(item.start))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isPast ? Color.secondary : Color.primary)
                if !item.isAnytime {
                    Text(Fmt.duration(item.durationMinutes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.timeColumn, alignment: .trailing)
            .padding(.top, 14)

            ZStack {
                if isCurrent {
                    Circle()
                        .stroke(item.tint, lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .phaseAnimator([false, true]) { content, expanded in
                            content
                                .scaleEffect(expanded ? 2.6 : 1)
                                .opacity(expanded ? 0 : 0.9)
                        } animation: { expanded in
                            expanded ? .easeOut(duration: 1.4) : nil
                        }
                }
                Circle()
                    .fill(item.isDone ? Color.secondary.opacity(0.5) : item.tint)
                    .frame(width: 10, height: 10)
                    .shadow(color: item.tint.opacity(isCurrent ? 0.9 : 0), radius: 6)
            }
            .frame(width: Self.railColumn, height: 14)
            .padding(.top, 21)

            AgendaCard(item: item)
        }
    }
}

private struct NowMarker: View {
    let date: Date
    let timeColumn: CGFloat
    let railColumn: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Text(Fmt.time(date))
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor))
                .frame(width: timeColumn, alignment: .trailing)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 9, height: 9)
                .shadow(color: Color.accentColor.opacity(0.8), radius: 6)
                .frame(width: railColumn)
            Capsule()
                .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, \(Fmt.time(date))")
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(.secondary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

/// Animated circular progress with a Jarvis gradient.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 6

    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    AngularGradient(colors: [JarvisTheme.cyan, JarvisTheme.blue, JarvisTheme.violet, JarvisTheme.cyan], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.2)) {
                shown = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                shown = newValue
            }
        }
    }
}

/// Friendly empty state with quick ways to get going.
struct EmptyStateCard: View {
    var title: String
    var message: String
    var showsSample: Bool = false
    var onAsk: () -> Void
    var onAdd: () -> Void
    var onSample: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(JarvisTheme.gradient)
                .symbolEffect(.breathe)
            Text(title)
                .font(.title3.bold())
                .fontDesign(.rounded)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(action: onAsk) {
                    Label("Ask Jarvis", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                Button(action: onAdd) {
                    Label("Add Plan", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
            }
            .padding(.top, 4)
            if showsSample {
                Button("Load a sample week", action: onSample)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }
}
