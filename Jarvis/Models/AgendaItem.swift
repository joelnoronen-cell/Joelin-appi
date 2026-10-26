import SwiftUI

/// A read-only snapshot of something on the agenda – either one of the
/// user's plans or an event pulled from the system calendar.
struct AgendaItem: Identifiable {
    enum Source {
        case plan(Plan)
        case event(CalendarEvent)
    }

    let id: String
    let source: Source
    let title: String
    let start: Date
    let end: Date
    let isAnytime: Bool
    let tint: Color
    let symbol: String
    let detail: String
    let isDone: Bool
    let isImportant: Bool

    var plan: Plan? {
        if case .plan(let plan) = source { return plan }
        return nil
    }

    var isEvent: Bool { plan == nil }

    var durationMinutes: Int {
        max(Int(end.timeIntervalSince(start) / 60), 0)
    }

    init(plan: Plan) {
        id = plan.uid.uuidString
        source = .plan(plan)
        title = plan.title
        start = plan.start
        end = plan.end
        isAnytime = plan.isAnytime
        tint = plan.category.color
        symbol = plan.category.symbol
        isDone = plan.isDone
        isImportant = plan.priority == .high

        var parts = [plan.category.title]
        if plan.isAnytime {
            parts.append("Anytime")
        } else {
            parts.append(Fmt.duration(plan.durationMinutes))
        }
        let firstNoteLine = plan.notes
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
        if let firstNoteLine, !firstNoteLine.isEmpty {
            parts.append(firstNoteLine)
        }
        detail = parts.joined(separator: " · ")
    }

    init(event: CalendarEvent) {
        id = event.id
        source = .event(event)
        title = event.title
        start = event.start
        end = event.end
        isAnytime = event.isAllDay
        tint = event.color
        symbol = "calendar"
        isDone = false
        isImportant = false

        var parts = [event.calendarName]
        if let location = event.location, !location.isEmpty {
            parts.append(location)
        } else if event.isAllDay {
            parts.append("All day")
        }
        detail = parts.joined(separator: " · ")
    }
}

/// Everything on one day, used by the week screens and the briefings.
struct DayAgenda: Identifiable {
    let day: Date
    let items: [AgendaItem]

    var id: Date { day }
    var doneCount: Int { items.filter(\.isDone).count }
}

enum Agenda {
    /// Plans and calendar events for `day`, in chronological order.
    static func items(
        on day: Date,
        plans: [Plan],
        events: [CalendarEvent],
        calendar: Calendar = .current
    ) -> [AgendaItem] {
        let dayPlans = plans
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .map(AgendaItem.init(plan:))
        let dayEvents = events.map(AgendaItem.init(event:))
        return (dayPlans + dayEvents).sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    /// The thing to focus on: whatever is happening now, otherwise the next
    /// unfinished timed item later today.
    static func focus(in items: [AgendaItem], now: Date) -> AgendaItem? {
        let open = items.filter { !$0.isAnytime && !$0.isDone }
        if let current = open.first(where: { $0.start <= now && $0.end > now }) {
            return current
        }
        return open.first { $0.start > now }
    }

    /// Default start time for a new plan on `day`: the next whole hour when
    /// it's today, otherwise 9 AM.
    static func suggestedStart(on day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now),
           let nextHour = calendar.date(byAdding: .hour, value: 1, to: now) {
            let parts = calendar.dateComponents([.year, .month, .day, .hour], from: nextHour)
            return calendar.date(from: parts) ?? nextHour
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}
