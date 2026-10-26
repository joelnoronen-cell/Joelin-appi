import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(JarvisStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \Plan.start) private var plans: [Plan]

    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.voiceEnabled) private var voiceEnabled = true
    @AppStorage(SettingsKey.voiceAccent) private var voiceAccent = "en-GB"
    @AppStorage(SettingsKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(SettingsKey.reminderLead) private var reminderLead = 10

    @State private var confirmWipe = false
    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var calendar = store.calendar

        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 18) {
                        JarvisOrb(size: 56, isActive: store.voice.isSpeaking, showsRings: false)
                            .padding(6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("J.A.R.V.I.S.")
                                .font(.title3.bold())
                                .fontDesign(.rounded)
                            Text("Just A Rather Very Intelligent Scheduler")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    TextField("Your name", text: $userName)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                } header: {
                    Text("What should Jarvis call you?")
                }

                Section {
                    Toggle(isOn: $voiceEnabled) {
                        Label("Speak replies", systemImage: "speaker.wave.2.fill")
                    }
                    Picker(selection: $voiceAccent) {
                        Text("British").tag("en-GB")
                        Text("American").tag("en-US")
                        Text("Australian").tag("en-AU")
                        Text("Irish").tag("en-IE")
                        Text("Indian").tag("en-IN")
                    } label: {
                        Label("Accent", systemImage: "globe")
                    }
                    Button {
                        let name = userName.trimmingCharacters(in: .whitespaces)
                        store.voice.speak(name.isEmpty ? "At your service." : "At your service, \(name).")
                    } label: {
                        Label("Test voice", systemImage: "waveform")
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Tap the orb on Today any time to hear your briefing. Download enhanced voices in Settings › Accessibility › Spoken Content for an even better Jarvis.")
                }

                Section {
                    Toggle(isOn: $calendar.isEnabled) {
                        Label("Show calendar events", systemImage: "calendar")
                    }
                    if calendar.isDenied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Label("Allow access in Settings", systemImage: "gear")
                        }
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Events from your calendars appear alongside your plans. Jarvis only reads them — it never changes your calendar.")
                }

                Section {
                    Toggle(isOn: $remindersEnabled) {
                        Label("Remind me before plans", systemImage: "bell.badge.fill")
                    }
                    if remindersEnabled {
                        Picker(selection: $reminderLead) {
                            ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                                Text(Fmt.duration(minutes) + " before").tag(minutes)
                            }
                        } label: {
                            Label("When", systemImage: "clock")
                        }
                    }
                    if notificationsDenied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Label("Allow notifications in Settings", systemImage: "gear")
                        }
                    }
                } header: {
                    Text("Reminders")
                }

                Section {
                    Button {
                        withAnimation(.smooth) { SampleData.load(into: context) }
                    } label: {
                        Label("Load sample week", systemImage: "wand.and.stars")
                    }
                    Button {
                        clearCompleted()
                    } label: {
                        Label("Clear completed plans", systemImage: "checkmark.circle")
                    }
                    .disabled(!plans.contains(where: \.isDone))
                    Button(role: .destructive) {
                        confirmWipe = true
                    } label: {
                        Label("Delete all plans", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(plans.isEmpty)
                } header: {
                    Text("Data")
                } footer: {
                    Text("\(Fmt.count(plans.count, "plan")) stored on this device.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuroraBackground() }
            .navigationTitle("Settings")
            .animation(.smooth, value: remindersEnabled)
            .animation(.smooth, value: calendar.isDenied)
            .onChange(of: calendar.isEnabled) { _, isOn in
                if isOn && !store.calendar.hasAccess {
                    Task { await store.calendar.enable() }
                }
            }
            .onChange(of: remindersEnabled) { _, isOn in
                updateReminders(isOn)
            }
            .onChange(of: reminderLead) {
                ReminderScheduler.resync(plans)
            }
            .onAppear {
                store.calendar.refreshStatus()
            }
            .confirmationDialog("Delete all plans?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete All", role: .destructive, action: deleteAll)
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func updateReminders(_ isOn: Bool) {
        guard isOn else {
            ReminderScheduler.cancelAll()
            return
        }
        Task {
            let granted = await ReminderScheduler.requestAuthorization()
            notificationsDenied = !granted
            if granted {
                ReminderScheduler.resync(plans)
            } else {
                remindersEnabled = false
            }
        }
    }

    private func clearCompleted() {
        withAnimation(.smooth) {
            for plan in plans where plan.isDone {
                ReminderScheduler.cancel(plan)
                context.delete(plan)
            }
        }
    }

    private func deleteAll() {
        ReminderScheduler.cancelAll()
        withAnimation(.smooth) {
            for plan in plans {
                context.delete(plan)
            }
        }
    }
}
