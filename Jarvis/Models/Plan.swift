import Foundation
import SwiftData

/// Something the user intends to do: a timed block ("Gym 7–8 AM") or an
/// "anytime" task that just belongs to a day ("Buy groceries").
@Model
final class Plan {
    var uid: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var start: Date = Date.now
    var durationMinutes: Int = 30
    /// No specific time – the plan belongs to the day of `start`.
    var isAnytime: Bool = false
    var categoryRaw: String = PlanCategory.personal.rawValue
    var priorityRaw: Int = PlanPriority.normal.rawValue
    var isDone: Bool = false
    var completedAt: Date?
    var remind: Bool = true
    var createdAt: Date = Date.now

    init(
        title: String,
        notes: String = "",
        start: Date,
        durationMinutes: Int = 30,
        isAnytime: Bool = false,
        category: PlanCategory = .personal,
        priority: PlanPriority = .normal,
        remind: Bool = true
    ) {
        self.uid = UUID()
        self.title = title
        self.notes = notes
        self.start = start
        self.durationMinutes = durationMinutes
        self.isAnytime = isAnytime
        self.categoryRaw = category.rawValue
        self.priorityRaw = priority.rawValue
        self.isDone = false
        self.completedAt = nil
        self.remind = remind
        self.createdAt = .now
    }

    var category: PlanCategory {
        get { PlanCategory(rawValue: categoryRaw) ?? .personal }
        set { categoryRaw = newValue.rawValue }
    }

    var priority: PlanPriority {
        get { PlanPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var end: Date {
        start.addingTimeInterval(TimeInterval(max(durationMinutes, 0) * 60))
    }

    static func make(from parsed: ParsedPlan) -> Plan {
        Plan(
            title: parsed.title,
            start: parsed.start,
            durationMinutes: parsed.durationMinutes,
            isAnytime: !parsed.hasTime,
            category: parsed.category,
            priority: parsed.priority
        )
    }
}
