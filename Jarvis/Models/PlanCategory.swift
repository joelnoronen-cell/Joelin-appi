import SwiftUI

enum PlanCategory: String, CaseIterable, Identifiable, Codable {
    case work, personal, health, study, social, errands

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .work: "briefcase.fill"
        case .personal: "sparkle"
        case .health: "figure.run"
        case .study: "book.fill"
        case .social: "person.2.fill"
        case .errands: "bag.fill"
        }
    }

    var color: Color {
        switch self {
        case .work: Color(hex: 0x3D8BFF)
        case .personal: Color(hex: 0xA26BFF)
        case .health: Color(hex: 0x2FD69A)
        case .study: Color(hex: 0xFFB13D)
        case .social: Color(hex: 0xFF5C9D)
        case .errands: Color(hex: 0x3FD4E8)
        }
    }

    /// Sensible length when the user doesn't say how long something takes.
    var defaultDuration: Int {
        switch self {
        case .work: 45
        case .personal: 30
        case .health: 60
        case .study: 60
        case .social: 90
        case .errands: 30
        }
    }
}

enum PlanPriority: Int, CaseIterable, Identifiable, Codable {
    case low = 0
    case normal = 1
    case high = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }
}
