import Foundation

/// Everything Jarvis says: greetings, daily and weekly briefings, answers.
enum Briefing {
    static func greeting(at date: Date, name: String) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        case 17..<22: base = "Good evening"
        default: base = "Burning the midnight oil"
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? base : "\(base), \(trimmed)"
    }

    // MARK: - Day

    static func today(_ items: [AgendaItem], now: Date) -> String {
        guard !items.isEmpty else {
            return "Your schedule is clear today. Tell me what's coming up and I'll keep track of it."
        }

        let remaining = items.filter { !$0.isDone }
        let done = items.count - remaining.count
        if remaining.isEmpty {
            return "All \(Fmt.count(items.count, "plan")) for today are done. Outstanding work — the rest of the day is yours."
        }

        var lines: [String] = []
        lines.append("You have \(Fmt.count(items.count, "plan")) today" + (done > 0 ? ", \(done) already done." : "."))

        let timed = remaining.filter { !$0.isAnytime }
        let current = timed.first { $0.start <= now && $0.end > now }
        let next = timed.first { $0.start > now }
        if let current {
            lines.append("Right now: \(current.title), until \(Fmt.time(current.end)).")
        }
        if let next {
            lines.append("Next up is \(next.title) at \(Fmt.time(next.start)), \(relative(from: now, to: next.start)).")
        } else if current == nil, !timed.isEmpty {
            lines.append("Nothing else is scheduled for later.")
        }

        let overdue = timed.filter { $0.end <= now && $0.plan != nil }
        if overdue.count == 1 {
            lines.append("One earlier plan is still unchecked.")
        } else if overdue.count > 1 {
            lines.append("\(overdue.count) earlier plans are still unchecked.")
        }

        if let important = remaining.first(where: { $0.isImportant && $0.id != next?.id && ($0.isAnytime || $0.end > now) }) {
            lines.append("Don't forget: \(important.title) is marked important.")
        }

        let anytime = remaining.filter(\.isAnytime)
        if anytime.count == 1 {
            lines.append("\(anytime[0].title) can happen any time today.")
        } else if anytime.count > 1 {
            lines.append("\(anytime.count) tasks can happen any time today.")
        }

        if let window = freeSlots(on: now, items: items, now: now).max(by: { $0.duration < $1.duration }),
           window.duration >= 60 * 60 {
            lines.append("Your longest free window is \(Fmt.time(window.start)) to \(Fmt.time(window.end)).")
        }
        return lines.joined(separator: " ")
    }

    static func day(_ day: Date, items: [AgendaItem], now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) {
            return today(items, now: now)
        }
        if day < calendar.startOfDay(for: now) {
            let done = items.filter(\.isDone).count
            guard !items.isEmpty else { return "\(subject(for: day, now: now)) was a quiet one — nothing was planned." }
            return "\(prefix(for: day, now: now)) you had \(Fmt.count(items.count, "plan")) and finished \(done)."
        }
        guard !items.isEmpty else {
            return "\(subject(for: day, now: now)) is completely free. Want me to plan something?"
        }
        let listed = items.prefix(4).map { item in
            item.isAnytime ? item.title : "\(item.title) at \(Fmt.time(item.start))"
        }
        var text = "\(prefix(for: day, now: now)) you have \(Fmt.count(items.count, "plan")): \(listed.formatted(.list(type: .and)))"
        if items.count > 4 {
            text += ", plus \(items.count - 4) more"
        }
        text += "."
        if let important = items.first(where: \.isImportant) {
            text += " \(important.title) is marked important."
        }
        return text
    }

    static func freeTime(on day: Date, items: [AgendaItem], now: Date) -> String {
        let calendar = Calendar.current
        if day < calendar.startOfDay(for: now) {
            return "That day is already behind us."
        }
        let slots = freeSlots(on: day, items: items, now: now)
        let lead = prefix(for: day, now: now)
        guard !slots.isEmpty else {
            return "\(lead) you're fully booked until 10 PM. I'd guard what's left of your evening."
        }
        if slots.count == 1, let only = slots.first {
            return "\(lead) you're free from \(Fmt.time(only.start)) to \(Fmt.time(only.end)) — \(Fmt.spokenDuration(Int(only.duration / 60))) in total."
        }
        let ranges = slots.prefix(3).map { "\(Fmt.time($0.start)) to \(Fmt.time($0.end))" }
        let total = Int(slots.reduce(0) { $0 + $1.duration } / 60)
        return "\(lead) you have \(Fmt.spokenDuration(total)) free: \(ranges.formatted(.list(type: .and)))."
    }

    // MARK: - Week

    static func week(_ days: [DayAgenda], now: Date) -> String {
        let total = days.reduce(0) { $0 + $1.items.count }
        guard total > 0 else {
            return "Your week is wide open. A blank canvas — tell me what you'd like to fit in."
        }
        let done = days.reduce(0) { $0 + $1.doneCount }
        let today = Calendar.current.startOfDay(for: now)

        var lines = ["You have \(Fmt.count(total, "plan")) this week."]
        if done > 0 {
            lines.append("\(done) already wrapped up.")
        }
        if let busiest = days.max(by: { $0.items.count < $1.items.count }), busiest.items.count > 1 {
            lines.append("\(weekday(busiest.day)) is the busiest, with \(busiest.items.count).")
        }
        if let free = days.first(where: { $0.items.isEmpty && $0.day >= today }) {
            lines.append("\(weekday(free.day)) is completely free.")
        }
        let important = days.flatMap(\.items).filter { $0.isImportant && !$0.isDone && $0.end >= now }
        if !important.isEmpty {
            let names = important.prefix(2).map(\.title)
            lines.append("Keep an eye on \(names.formatted(.list(type: .and))).")
        }
        return lines.joined(separator: " ")
    }

    // MARK: - Confirmations

    static func confirmation(for plan: ParsedPlan, now: Date, remindersOn: Bool, leadMinutes: Int) -> String {
        let opener = ["Done.", "Consider it done.", "Noted.", "On it.", "Got it."].randomElement() ?? "Done."
        var when = dayPhrase(for: plan.start, now: now)
        if plan.hasTime {
            when += " at \(Fmt.time(plan.start))"
        }
        var text = "\(opener) \(plan.title), \(when)."
        if plan.hasTime && remindersOn {
            text += " I'll remind you \(Fmt.spokenDuration(leadMinutes)) before."
        }
        return text
    }

    // MARK: - Helpers

    /// Open windows of at least 30 minutes between 8 AM and 10 PM.
    static func freeSlots(on day: Date, items: [AgendaItem], now: Date) -> [DateInterval] {
        let calendar = Calendar.current
        guard let dayStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day),
              let dayEnd = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day) else { return [] }

        var cursor = dayStart
        if calendar.isDate(day, inSameDayAs: now), now > cursor {
            cursor = roundUp(now, toMinutes: 15)
        }
        guard cursor < dayEnd else { return [] }

        let busy = items
            .filter { !$0.isAnytime && !$0.isDone }
            .sorted { $0.start < $1.start }

        var slots: [DateInterval] = []
        for item in busy {
            if item.end <= cursor { continue }
            if item.start >= dayEnd { break }
            if item.start > cursor {
                slots.append(DateInterval(start: cursor, end: item.start))
            }
            cursor = max(cursor, item.end)
            if cursor >= dayEnd { break }
        }
        if cursor < dayEnd {
            slots.append(DateInterval(start: cursor, end: dayEnd))
        }
        return slots.filter { $0.duration >= 30 * 60 }
    }

    static func relative(from now: Date, to date: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded())
        if minutes <= 1 { return "starting any moment" }
        if minutes < 60 { return "in \(minutes) minutes" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest < 10 { return hours == 1 ? "in an hour" : "in \(hours) hours" }
        if rest > 50 { return "in about \(hours + 1) hours" }
        return "in \(Fmt.spokenDuration(minutes))"
    }

    /// "today", "tomorrow", "on Friday", "on October 30".
    static func dayPhrase(for date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if (2...6).contains(days) { return "on \(weekday(date))" }
        return "on \(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))"
    }

    private static func prefix(for day: Date, now: Date) -> String {
        let phrase = dayPhrase(for: day, now: now)
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    private static func subject(for day: Date, now: Date) -> String {
        var phrase = dayPhrase(for: day, now: now)
        if phrase.hasPrefix("on ") { phrase.removeFirst(3) }
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }

    private static func roundUp(_ date: Date, toMinutes step: Int) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trimmed = calendar.date(from: parts) ?? date
        let remainder = (parts.minute ?? 0) % step
        return remainder == 0 ? trimmed : trimmed.addingTimeInterval(TimeInterval((step - remainder) * 60))
    }
}
