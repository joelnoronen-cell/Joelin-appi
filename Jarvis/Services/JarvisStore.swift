import Observation
import SwiftData
import SwiftUI

/// Sheets that can be presented from anywhere in the app.
enum SheetRoute: Identifiable {
    case newPlan(Date)
    case edit(Plan)
    case ask

    var id: String {
        switch self {
        case .newPlan(let date): "new-\(date.timeIntervalSince1970)"
        case .edit(let plan): "edit-\(plan.uid.uuidString)"
        case .ask: "ask"
        }
    }
}

/// App-wide state shared through the environment.
@MainActor
@Observable
final class JarvisStore {
    var route: SheetRoute?
    let voice = JarvisVoice()
    let calendar = CalendarService()

    func agenda(on day: Date, plans: [Plan]) -> [AgendaItem] {
        Agenda.items(on: day, plans: plans, events: calendar.events(on: day))
    }

    func week(containing date: Date, plans: [Plan]) -> [DayAgenda] {
        Calendar.current.daysOfWeek(containing: date).map { day in
            DayAgenda(day: day, items: agenda(on: day, plans: plans))
        }
    }
}

/// Mutations shared by rows, cards and context menus.
@MainActor
enum PlanActions {
    static func toggleDone(_ plan: Plan) {
        withAnimation(.bouncy(duration: 0.45)) {
            plan.isDone.toggle()
            plan.completedAt = plan.isDone ? .now : nil
        }
        ReminderScheduler.sync(plan)
    }

    static func moveToTomorrow(_ plan: Plan) {
        withAnimation(.smooth) {
            plan.start = Calendar.current.date(byAdding: .day, value: 1, to: plan.start) ?? plan.start
            plan.isDone = false
            plan.completedAt = nil
        }
        ReminderScheduler.sync(plan)
    }

    static func duplicate(_ plan: Plan, in context: ModelContext) {
        let copy = Plan(
            title: plan.title,
            notes: plan.notes,
            start: plan.start,
            durationMinutes: plan.durationMinutes,
            isAnytime: plan.isAnytime,
            category: plan.category,
            priority: plan.priority,
            remind: plan.remind
        )
        withAnimation(.smooth) {
            context.insert(copy)
        }
        ReminderScheduler.sync(copy)
    }

    static func delete(_ plan: Plan, in context: ModelContext) {
        ReminderScheduler.cancel(plan)
        withAnimation(.smooth) {
            context.delete(plan)
        }
    }
}
