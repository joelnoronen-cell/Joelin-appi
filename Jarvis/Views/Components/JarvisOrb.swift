import SwiftUI

/// Jarvis' face: a swirling plasma core behind a Liquid Glass sphere, with
/// HUD rings orbiting around it. Spins up and pulses while Jarvis talks.
struct JarvisOrb: View {
    var size: CGFloat = 120
    var isActive: Bool = false
    var showsRings: Bool = true
    var usesGlass: Bool = true
    var isAnimated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let palette: [Color] = [
        JarvisTheme.cyan, JarvisTheme.blue, JarvisTheme.violet, JarvisTheme.pink, JarvisTheme.cyan,
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !isAnimated)) { context in
            orb(at: context.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func orb(at t: TimeInterval) -> some View {
        let speed = isActive ? 2.4 : 0.6
        let breathe = 1 + (isActive ? 0.06 : 0.025) * sin(t * (isActive ? 7 : 1.6))

        return ZStack {
            // Outer glow, kept inside the glass so the rim and rings stay crisp.
            Circle()
                .fill(AngularGradient(colors: Self.palette, center: .center))
                .rotationEffect(.radians(t * speed))
                .blur(radius: size * 0.12)
                .scaleEffect((isActive ? 0.95 : 0.84) * breathe)
                .opacity(isActive ? 1 : 0.8)

            // Counter-rotating plasma core.
            Circle()
                .fill(AngularGradient(colors: Self.palette.reversed(), center: .center))
                .rotationEffect(.radians(-t * speed * 1.4))
                .frame(width: size * 0.58, height: size * 0.58)
                .blur(radius: size * 0.07)

            // Hot white center.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.95), .white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.24
                    )
                )
                .frame(width: size * 0.5, height: size * 0.5)
                .scaleEffect(breathe)
                .blendMode(.plusLighter)

            if usesGlass {
                Circle()
                    .fill(.clear)
                    .glassEffect(.clear.interactive(), in: .circle)
            }

            if showsRings {
                Circle()
                    .trim(from: 0.05, to: 0.42)
                    .stroke(JarvisTheme.cyan.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: size * 1.28, height: size * 1.28)
                    .rotationEffect(.radians(t * (isActive ? 1.8 : 0.5)))
                Circle()
                    .trim(from: 0.55, to: 0.9)
                    .stroke(JarvisTheme.cyan.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: size * 1.28, height: size * 1.28)
                    .rotationEffect(.radians(t * (isActive ? 1.8 : 0.5)))
                Circle()
                    .trim(from: 0.2, to: 0.7)
                    .stroke(
                        JarvisTheme.violet.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 5])
                    )
                    .frame(width: size * 1.45, height: size * 1.45)
                    .rotationEffect(.radians(-t * (isActive ? 1.2 : 0.3)))
            }
        }
        .scaleEffect(breathe)
    }
}

#Preview {
    VStack(spacing: 60) {
        JarvisOrb(size: 140)
        JarvisOrb(size: 140, isActive: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AuroraBackground())
}
