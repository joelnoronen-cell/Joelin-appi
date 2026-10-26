import Foundation
import SwiftData

/// A believable week of plans so a fresh install has something to show.
@MainActor
enum SampleData {
    private struct Entry {
        let day: Int
        let hour: Int?
        let minute: Int
        let title: String
        let category: PlanCategory
        let duration: Int
        let priority: PlanPriority
        let notes: String

        init(_ day: Int, _ hour: Int?, _ minute: Int = 0, _ title: String, _ category: PlanCategory,
             _ duration: Int = 30, _ priority: PlanPriority = .normal, notes: String = "") {
            self.day = day
            self.hour = hour
            self.minute = minute
            self.title = title
            self.category = category
            self.duration = duration
            self.priority = priority
            self.notes = notes
        }
    }

    private static let entries: [Entry] = [
        Entry(-1, 9, 0, "1:1 with manager", .work, 30),
        Entry(-1, nil, 0, "Laundry", .errands),
        Entry(0, 7, 0, "Morning run", .health, 45, notes: "5 km easy pace"),
        Entry(0, 9, 30, "Team stand-up", .work, 15),
        Entry(0, 11, 0, "Design review", .work, 60, .high),
        Entry(0, 13, 0, "Lunch with Maya", .social, 60),
        Entry(0, 14, 30, "Deep work: project proposal", .work, 120, notes: "Phones off. Outline, then draft."),
        Entry(0, nil, 0, "Buy groceries", .errands),
        Entry(0, 21, 0, "Read 20 pages", .study, 30),
        Entry(1, 7, 30, "Gym — legs", .health, 60),
        Entry(1, 10, 0, "Client call", .work, 45, .high),
        Entry(1, 16, 0, "Dentist", .health, 45),
        Entry(1, 19, 0, "Call mom", .social, 30),
        Entry(2, 15, 0, "Study session: physics", .study, 120),
        Entry(2, nil, 0, "Pay rent", .errands, 30, .high),
        Entry(3, 8, 0, "Yoga", .health, 60),
        Entry(3, 10, 0, "Sprint planning", .work, 90),
        Entry(3, 20, 0, "Dinner with friends", .social, 120),
        Entry(4, 17, 0, "Weekly review", .personal, 30),
        Entry(4, 20, 30, "Movie night", .social, 150),
        Entry(5, 9, 0, "Long run", .health, 90),
        Entry(5, 11, 0, "Farmers market", .errands, 60),
    ]

    static func load(into context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for entry in entries {
            guard let day = calendar.date(byAdding: .day, value: entry.day, to: today) else { continue }
            let start: Date
            if let hour = entry.hour {
                start = calendar.date(bySettingHour: hour, minute: entry.minute, second: 0, of: day) ?? day
            } else {
                start = day
            }
            let plan = Plan(
                title: entry.title,
                notes: entry.notes,
                start: start,
                durationMinutes: entry.duration,
                isAnytime: entry.hour == nil,
                category: entry.category,
                priority: entry.priority
            )
            if plan.end < now && !(entry.day == 0 && entry.hour == nil) {
                plan.isDone = true
                plan.completedAt = plan.end
            }
            context.insert(plan)
            ReminderScheduler.sync(plan)
        }
    }
}
