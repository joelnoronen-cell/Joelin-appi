import SwiftData
import SwiftUI

struct PlanEditorView: View {
    enum Mode {
        case create(Date)
        case edit(Plan)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var title: String
    @State private var notes: String
    @State private var start: Date
    @State private var isAnytime: Bool
    @State private var duration: Int
    @State private var category: PlanCategory
    @State private var priority: PlanPriority
    @State private var remind: Bool
    @State private var categoryTouched: Bool
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    private static let durations = [15, 30, 45, 60, 90, 120, 180]

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create(let date):
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _start = State(initialValue: date)
            _isAnytime = State(initialValue: false)
            _duration = State(initialValue: 30)
            _category = State(initialValue: .personal)
            _priority = State(initialValue: .normal)
            _remind = State(initialValue: true)
            _categoryTouched = State(initialValue: false)
        case .edit(let plan):
            _title = State(initialValue: plan.title)
            _notes = State(initialValue: plan.notes)
            _start = State(initialValue: plan.start)
            _isAnytime = State(initialValue: plan.isAnytime)
            _duration = State(initialValue: plan.durationMinutes)
            _category = State(initialValue: plan.category)
            _priority = State(initialValue: plan.priority)
            _remind = State(initialValue: plan.remind)
            _categoryTouched = State(initialValue: true)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    titleCard
                    categoryRow
                    scheduleCard
                    detailsCard
                    if isEditing {
                        deleteButton
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background { AuroraBackground() }
            .navigationTitle(isEditing ? "Edit Plan" : "New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: save) {
                        Label("Save", systemImage: "checkmark")
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this plan?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Plan", role: .destructive, action: deletePlan)
            }
        }
        .onAppear {
            if !isEditing { titleFocused = true }
        }
    }

    // MARK: - Sections

    private var titleCard: some View {
        HStack(spacing: 14) {
            Image(systemName: category.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(category.color)
                .frame(width: 48, height: 48)
                .background(category.color.opacity(0.2), in: .circle)
                .contentTransition(.symbolEffect(.replace))
            TextField("What's the plan?", text: $title, axis: .vertical)
                .font(.title3.weight(.semibold))
                .lineLimit(1...3)
                .focused($titleFocused)
        }
        .padding(16)
        .glassEffect(.regular.tint(category.color.opacity(0.14)), in: .rect(cornerRadius: 26))
        .onChange(of: title) { _, newValue in
            guard !categoryTouched, let guess = PlanParser.guessCategory(in: newValue), guess != category else { return }
            withAnimation(.snappy) {
                category = guess
                duration = guess.defaultDuration
            }
        }
    }

    private var categoryRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(PlanCategory.allCases) { item in
                    let isSelected = item == category
                    Button {
                        categoryTouched = true
                        withAnimation(.snappy) {
                            category = item
                        }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(isSelected ? .regular.tint(item.color).interactive() : .regular.interactive(), in: .capsule)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
        .sensoryFeedback(.selection, trigger: category)
    }

    private var scheduleCard: some View {
        VStack(spacing: 14) {
            Toggle(isOn: $isAnytime.animation(.snappy)) {
                Label("Anytime that day", systemImage: "sun.horizon.fill")
            }

            Divider()

            DatePicker(
                selection: $start,
                displayedComponents: isAnytime ? DatePickerComponents.date : [.date, .hourAndMinute]
            ) {
                Label("When", systemImage: "calendar")
            }

            if !isAnytime {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Duration", systemImage: "hourglass")
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(durationOptions, id: \.self) { minutes in
                                let isSelected = minutes == duration
                                Button {
                                    withAnimation(.snappy) { duration = minutes }
                                } label: {
                                    Text(Fmt.duration(minutes))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background {
                                            if isSelected {
                                                Capsule().fill(category.color.gradient)
                                            } else {
                                                Capsule().fill(Color.primary.opacity(0.08))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                Toggle(isOn: $remind) {
                    Label("Remind me", systemImage: "bell.badge.fill")
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Priority", systemImage: "flag.fill")
            Picker("Priority", selection: $priority) {
                ForEach(PlanPriority.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...8)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Delete Plan", systemImage: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
    }

    private var durationOptions: [Int] {
        Set(Self.durations + [duration]).sorted()
    }

    // MARK: - Actions

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let plan: Plan
        switch mode {
        case .create:
            plan = Plan(title: trimmed, start: start)
            context.insert(plan)
        case .edit(let existing):
            plan = existing
        }
        withAnimation(.smooth) {
            plan.title = trimmed
            plan.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            plan.start = isAnytime ? Calendar.current.startOfDay(for: start) : start
            plan.isAnytime = isAnytime
            plan.durationMinutes = duration
            plan.category = category
            plan.priority = priority
            plan.remind = remind
        }
        ReminderScheduler.sync(plan)
        dismiss()
    }

    private func deletePlan() {
        guard case .edit(let plan) = mode else { return }
        PlanActions.delete(plan, in: context)
        dismiss()
    }
}
