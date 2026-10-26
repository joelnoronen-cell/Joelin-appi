import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today, week, settings
}

struct RootView: View {
    @State private var store = JarvisStore()
    @State private var tab: AppTab = .today
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("Week", systemImage: "calendar", value: AppTab.week) {
                WeekView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            AskJarvisBar()
        }
        .sensoryFeedback(.selection, trigger: tab)
        .sheet(item: $store.route) { route in
            switch route {
            case .newPlan(let date):
                PlanEditorView(mode: .create(date))
            case .edit(let plan):
                PlanEditorView(mode: .edit(plan))
            case .ask:
                AskJarvisView()
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.calendar.refreshStatus()
            }
        }
        #if DEBUG
        .onAppear(perform: applyDebugLaunchArguments)
        #endif
        .environment(store)
    }

    #if DEBUG
    @Environment(\.modelContext) private var context

    /// Launch arguments used by the screenshot workflow, e.g.
    /// `-JarvisSeedSampleData YES -JarvisTab week -JarvisOpenAsk YES`.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "JarvisSeedSampleData"),
           (try? context.fetchCount(FetchDescriptor<Plan>())) == 0 {
            SampleData.load(into: context)
        }
        switch defaults.string(forKey: "JarvisTab") {
        case "week": tab = .week
        case "settings": tab = .settings
        default: break
        }
        if defaults.bool(forKey: "JarvisOpenAsk") {
            store.route = .ask
        }
    }
    #endif
}

/// The glass "Ask Jarvis" bar that floats above the tab bar.
private struct AskJarvisBar: View {
    @Environment(JarvisStore.self) private var store

    var body: some View {
        Button {
            store.route = .ask
        } label: {
            HStack(spacing: 10) {
                JarvisOrb(size: 24, isActive: store.voice.isSpeaking, showsRings: false, usesGlass: false)
                Text("Ask Jarvis")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JarvisTheme.gradient)
                    .symbolEffect(.breathe)
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Jarvis")
    }
}

#Preview {
    RootView()
        .modelContainer(for: Plan.self, inMemory: true)
}
