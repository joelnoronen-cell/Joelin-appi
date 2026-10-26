import SwiftData
import SwiftUI

/// One line in the conversation with Jarvis.
struct ChatMessage: Identifiable {
    enum Role { case user, jarvis }

    let id = UUID()
    let role: Role
    var text: String
    /// Summary of a plan Jarvis just added (shown as a card).
    var parsed: ParsedPlan?
    /// The inserted plan, kept so it can be undone.
    var plan: Plan?
    var undone = false
}

struct AskJarvisView: View {
    @Environment(JarvisStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Plan.start) private var plans: [Plan]
    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.voiceEnabled) private var voiceEnabled = true
    @AppStorage(SettingsKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(SettingsKey.reminderLead) private var reminderLead = 10

    @State private var input = ""
    @State private var messages: [ChatMessage] = []
    @State private var isThinking = false
    @FocusState private var inputFocused: Bool
    @Namespace private var glassNamespace

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    JarvisOrb(size: 112, isActive: isThinking || store.voice.isSpeaking)
                        .padding(.vertical, 34)

                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            isLatest: message.id == messages.last?.id,
                            onUndo: { undo(message) }
                        )
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.9, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)),
                                removal: .opacity
                            )
                        )
                    }

                    if isThinking {
                        ThinkingBubble()
                            .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                    }

                    if messages.count <= 1 && !isThinking {
                        SuggestionGrid(onPick: pick)
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                composer
            }
            .background { AuroraBackground() }
            .navigationTitle("Jarvis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        store.voice.stop()
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
        }
        .onAppear(perform: greetIfNeeded)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 10) {
            if let preview = IntentPreview(intent: PlanParser().interpret(input)) {
                IntentPreviewChip(preview: preview)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
            }

            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 10) {
                    TextField("“Dentist Friday at 3pm”", text: $input)
                        .focused($inputFocused)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .padding(.horizontal, 20)
                        .frame(height: 52)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .glassEffectID("field", in: glassNamespace)

                    if !trimmedInput.isEmpty {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(Color.accentColor).interactive(), in: .circle)
                        .glassEffectID("send", in: glassNamespace)
                        .accessibilityLabel("Send")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .animation(.bouncy(duration: 0.4), value: trimmedInput.isEmpty)
        .animation(.smooth(duration: 0.3), value: IntentPreview(intent: PlanParser().interpret(input)))
    }

    // MARK: - Actions

    private func greetIfNeeded() {
        guard messages.isEmpty else { return }
        let greeting = Briefing.greeting(at: .now, name: userName)
        messages = [
            ChatMessage(
                role: .jarvis,
                text: "\(greeting). Tell me what's coming up and I'll slot it in — or ask me about your day."
            )
        ]
    }

    private func pick(_ suggestion: Suggestion) {
        if suggestion.sendsImmediately {
            input = suggestion.text
            send()
        } else {
            withAnimation(.smooth) {
                input = suggestion.text
            }
            inputFocused = true
        }
    }

    private func send() {
        let text = trimmedInput
        guard !text.isEmpty, !isThinking else { return }
        let intent = PlanParser().interpret(text)
        input = ""
        withAnimation(.smooth(duration: 0.35)) {
            messages.append(ChatMessage(role: .user, text: text))
            isThinking = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            let reply = respond(to: intent)
            withAnimation(.smooth(duration: 0.4)) {
                isThinking = false
                messages.append(reply)
            }
            if voiceEnabled {
                store.voice.speak(reply.text)
            }
        }
    }

    private func respond(to intent: JarvisIntent) -> ChatMessage {
        let now = Date.now
        switch intent {
        case .add(let parsed):
            let plan = Plan.make(from: parsed)
            context.insert(plan)
            ReminderScheduler.sync(plan)
            let text = Briefing.confirmation(
                for: parsed,
                now: now,
                remindersOn: remindersEnabled,
                leadMinutes: reminderLead
            )
            return ChatMessage(role: .jarvis, text: text, parsed: parsed, plan: plan)

        case .dayBriefing(let day):
            let items = store.agenda(on: day, plans: plans)
            return ChatMessage(role: .jarvis, text: Briefing.day(day, items: items, now: now))

        case .weekBriefing(let date):
            let week = store.week(containing: date, plans: plans)
            return ChatMessage(role: .jarvis, text: Briefing.week(week, now: now))

        case .freeTime(let day):
            let items = store.agenda(on: day, plans: plans)
            return ChatMessage(role: .jarvis, text: Briefing.freeTime(on: day, items: items, now: now))

        case .setName(let name):
            userName = name
            return ChatMessage(role: .jarvis, text: "Very well. I'll call you \(name) from now on.")

        case .empty:
            return ChatMessage(role: .jarvis, text: "I didn't quite catch that. Try something like “Gym tomorrow at 7am”.")
        }
    }

    private func undo(_ message: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }),
              let plan = messages[index].plan else { return }
        ReminderScheduler.cancel(plan)
        withAnimation(.smooth) {
            messages[index].plan = nil
            messages[index].undone = true
            context.delete(plan)
            messages.append(ChatMessage(role: .jarvis, text: "Removed. As if it never happened."))
        }
    }
}

// MARK: - Bubbles

private struct MessageBubble: View {
    let message: ChatMessage
    let isLatest: Bool
    var onUndo: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 48)
            } else {
                JarvisOrb(size: 26, showsRings: false, usesGlass: false, isAnimated: isLatest)
                    .padding(.bottom, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                if message.role == .jarvis {
                    TypewriterText(text: message.text)
                        .font(.body)
                } else {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(.white)
                }

                if let parsed = message.parsed {
                    PlanSummaryCard(plan: parsed, undone: message.undone)
                }

                if message.plan != nil {
                    Button(action: onUndo) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(
                message.role == .user ? .regular.tint(Color.accentColor.opacity(0.85)) : .regular,
                in: .rect(cornerRadius: 22)
            )

            if message.role == .jarvis {
                Spacer(minLength: 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct PlanSummaryCard: View {
    let plan: ParsedPlan
    let undone: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plan.category.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(plan.category.color)
                .frame(width: 34, height: 34)
                .background(plan.category.color.opacity(0.18), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(undone)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if plan.priority == .high {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 14))
        .opacity(undone ? 0.5 : 1)
    }

    private var summary: String {
        var parts = [Briefing.dayPhrase(for: plan.start, now: .now).capitalizedFirst]
        if plan.hasTime {
            parts.append(Fmt.time(plan.start))
            parts.append(Fmt.duration(plan.durationMinutes))
        }
        parts.append(plan.category.title)
        return parts.joined(separator: " · ")
    }
}

private struct ThinkingBubble: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            JarvisOrb(size: 26, isActive: true, showsRings: false, usesGlass: false)
                .padding(.bottom, 4)
            Image(systemName: "ellipsis")
                .font(.title3.weight(.bold))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                .foregroundStyle(.secondary)
                .frame(width: 54, height: 22)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
            Spacer()
        }
        .accessibilityLabel("Jarvis is thinking")
    }
}

// MARK: - Live preview

/// What Jarvis will do with the current input, shown above the field.
private struct IntentPreview: Equatable {
    let symbol: String
    let text: String
    let tint: Color

    init?(intent: JarvisIntent) {
        switch intent {
        case .add(let plan):
            var parts = [Briefing.dayPhrase(for: plan.start, now: .now).capitalizedFirst]
            if plan.hasTime {
                parts.append(Fmt.time(plan.start))
                parts.append(Fmt.duration(plan.durationMinutes))
            } else {
                parts.append("Anytime")
            }
            parts.append(plan.category.title)
            symbol = plan.category.symbol
            text = "\(plan.title) — " + parts.joined(separator: " · ")
            tint = plan.category.color
        case .dayBriefing(let day):
            symbol = "text.bubble.fill"
            text = "Brief you on \(Briefing.dayPhrase(for: day, now: .now).replacingOccurrences(of: "on ", with: ""))"
            tint = JarvisTheme.cyan
        case .weekBriefing:
            symbol = "calendar"
            text = "Brief you on the week"
            tint = JarvisTheme.cyan
        case .freeTime(let day):
            symbol = "hourglass"
            text = "Find free time \(Briefing.dayPhrase(for: day, now: .now))"
            tint = Color(hex: 0x2FD69A)
        case .setName(let name):
            symbol = "person.crop.circle"
            text = "Call you \(name)"
            tint = JarvisTheme.violet
        case .empty:
            return nil
        }
    }
}

private struct IntentPreviewChip: View {
    let preview: IntentPreview

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: preview.symbol)
                .foregroundStyle(preview.tint)
                .contentTransition(.symbolEffect(.replace))
            Text(preview.text)
                .lineLimit(1)
                .contentTransition(.interpolate)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(preview.tint.opacity(0.18)), in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Suggestions

struct Suggestion: Identifiable {
    let text: String
    let symbol: String
    let tint: Color
    let sendsImmediately: Bool

    var id: String { text }

    static let all: [Suggestion] = [
        Suggestion(text: "What's on today?", symbol: "sun.max.fill", tint: JarvisTheme.cyan, sendsImmediately: true),
        Suggestion(text: "Am I free tomorrow afternoon?", symbol: "hourglass", tint: Color(hex: 0x2FD69A), sendsImmediately: true),
        Suggestion(text: "Gym tomorrow at 7am for 1h", symbol: "figure.run", tint: PlanCategory.health.color, sendsImmediately: false),
        Suggestion(text: "Dinner with Sam Friday 8pm", symbol: "fork.knife", tint: PlanCategory.social.color, sendsImmediately: false),
        Suggestion(text: "Brief me on my week", symbol: "calendar", tint: JarvisTheme.violet, sendsImmediately: true),
        Suggestion(text: "Finish report by Thursday 5pm!!", symbol: "flag.fill", tint: .orange, sendsImmediately: false),
    ]
}

private struct SuggestionGrid: View {
    var onPick: (Suggestion) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Suggestion.all) { suggestion in
                Button {
                    onPick(suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: suggestion.symbol)
                            .font(.headline)
                            .foregroundStyle(suggestion.tint)
                        Text(suggestion.text)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                    .padding(14)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                    .contentShape(.rect(cornerRadius: 22))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension String {
    var capitalizedFirst: String {
        self.prefix(1).uppercased() + self.dropFirst()
    }
}
