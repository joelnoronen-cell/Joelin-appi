import SwiftUI

/// Slowly drifting mesh gradient that gives the Liquid Glass something rich
/// to refract. Deep navy with a cyan core at night, soft pastels by day.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(at: t),
                colors: colorScheme == .dark ? Self.night : Self.day
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static func points(at t: TimeInterval) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.21))
        let b = Float(cos(t * 0.17))
        let c = Float(sin(t * 0.13 + 1.3))
        return [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5 + 0.25 * a, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.45 + 0.2 * b), SIMD2<Float>(0.5 + 0.22 * c, 0.5 + 0.2 * a), SIMD2<Float>(1, 0.55 + 0.2 * c),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5 + 0.25 * b, 1), SIMD2<Float>(1, 1),
        ]
    }

    private static let night: [Color] = [
        Color(hex: 0x050815), Color(hex: 0x0B1D45), Color(hex: 0x080F24),
        Color(hex: 0x10305F), Color(hex: 0x0F6A93), Color(hex: 0x2A1663),
        Color(hex: 0x04091A), Color(hex: 0x0D2B55), Color(hex: 0x1A0D3D),
    ]

    private static let day: [Color] = [
        Color(hex: 0xF3F7FF), Color(hex: 0xD8E7FF), Color(hex: 0xEEEBFF),
        Color(hex: 0xD3F0FF), Color(hex: 0xA6D6FF), Color(hex: 0xE2D6FF),
        Color(hex: 0xF7F9FF), Color(hex: 0xD6EBFF), Color(hex: 0xF0E4FF),
    ]
}
