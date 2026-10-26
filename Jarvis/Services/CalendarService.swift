import EventKit
import Observation
import SwiftUI

/// An event from the user's system calendar.
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let calendarName: String
    let color: Color

    init(_ event: EKEvent) {
        let start: Date = event.startDate ?? .now
        let identifier: String = event.eventIdentifier ?? UUID().uuidString
        // Recurring events share an identifier, so add the occurrence date.
        id = "\(identifier)-\(Int(start.timeIntervalSince1970))"
        title = event.title ?? "Untitled event"
        self.start = start
        end = event.endDate ?? start
        isAllDay = event.isAllDay
        location = event.location
        calendarName = event.calendar?.title ?? "Calendar"
        if let cgColor = event.calendar?.cgColor {
            color = Color(cgColor: cgColor)
        } else {
            color = .blue
        }
    }
}

/// Read-only bridge to EventKit so calendar events appear next to plans.
@MainActor
@Observable
final class CalendarService {
    private let store = EKEventStore()
    @ObservationIgnored private var cache: [Date: [CalendarEvent]] = [:]
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    /// Bumped whenever cached events become stale so views re-query.
    private(set) var revision = 0
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private var enabledStorage = UserDefaults.standard.bool(forKey: SettingsKey.calendarEnabled)

    var isEnabled: Bool {
        get { enabledStorage }
        set {
            enabledStorage = newValue
            UserDefaults.standard.set(newValue, forKey: SettingsKey.calendarEnabled)
            invalidate()
        }
    }

    var hasAccess: Bool { status == .fullAccess }
    var isDenied: Bool { status == .denied || status == .restricted }
    var isActive: Bool { isEnabled && hasAccess }

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidate()
            }
        }
    }

    /// Asks for calendar access if needed, then turns the integration on.
    func enable() async {
        if status == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
        }
        isEnabled = hasAccess
    }

    func refreshStatus() {
        let current = EKEventStore.authorizationStatus(for: .event)
        if current != status {
            status = current
            invalidate()
        }
    }

    func events(on day: Date) -> [CalendarEvent] {
        _ = revision
        guard isActive else { return [] }
        let calendar = Calendar.current
        let key = calendar.startOfDay(for: day)
        if let cached = cache[key] { return cached }
        guard let end = calendar.date(byAdding: .day, value: 1, to: key) else { return [] }
        let predicate = store.predicateForEvents(withStart: key, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .map(CalendarEvent.init)
            .sorted { $0.start < $1.start }
        cache[key] = events
        return events
    }

    private func invalidate() {
        cache.removeAll()
        revision += 1
    }
}
