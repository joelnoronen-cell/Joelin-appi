import SwiftUI

/// Reveals its text character by character the first time it appears, the
/// way Jarvis "types" a reply. Later text changes update instantly. Layout
/// is stable because hidden characters are drawn clear rather than removed.
struct TypewriterText: View {
    let text: String
    var characterDelay: Duration = .milliseconds(16)

    @State private var visibleCount = 0
    @State private var hasFinished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(attributed)
            .accessibilityLabel(text)
            .task(id: text) {
                await reveal()
            }
    }

    private var attributed: AttributedString {
        var string = AttributedString(text)
        let shown = hasFinished ? text.count : min(visibleCount, text.count)
        if shown < text.count {
            let index = string.characters.index(string.startIndex, offsetBy: shown)
            string[index..<string.endIndex].foregroundColor = Color.clear
        }
        return string
    }

    private func reveal() async {
        if hasFinished || reduceMotion {
            hasFinished = true
            return
        }
        // Reveal a few characters per frame so long briefings still finish
        // in about a second and a half.
        let step = max(1, Int((Double(text.count) / 90).rounded(.up)))
        visibleCount = 0
        while visibleCount < text.count {
            visibleCount = min(visibleCount + step, text.count)
            do {
                try await Task.sleep(for: characterDelay)
            } catch {
                return
            }
        }
        hasFinished = true
    }
}
