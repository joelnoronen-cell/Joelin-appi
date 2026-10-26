import SwiftUI

enum Fmt {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Compact duration for labels: "45m", "1h", "1h 30m".
    static func duration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(max(minutes, 0))m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Duration that reads naturally out loud: "1 hour 30 minutes".
    static func spokenDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append(count(hours, "hour")) }
        if rest > 0 || hours == 0 { parts.append(count(rest, "minute")) }
        return parts.joined(separator: " ")
    }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(value == 1 ? noun : noun + "s")"
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum JarvisTheme {
    static let cyan = Color(hex: 0x4FD1FF)
    static let blue = Color(hex: 0x3A6BFF)
    static let violet = Color(hex: 0x8B5CFF)
    static let pink = Color(hex: 0xFF5AB8)

    static let gradient = LinearGradient(
        colors: [cyan, blue, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }

    /// The seven days (each at midnight) of the week containing `date`.
    func daysOfWeek(containing date: Date) -> [Date] {
        let start = startOfWeek(for: date)
        return (0..<7).compactMap { self.date(byAdding: .day, value: $0, to: start) }
    }
}

enum SettingsKey {
    static let userName = "userName"
    static let voiceEnabled = "voiceEnabled"
    static let voiceAccent = "voiceAccent"
    static let remindersEnabled = "remindersEnabled"
    static let reminderLead = "reminderLead"
    static let calendarEnabled = "calendarEnabled"
}
