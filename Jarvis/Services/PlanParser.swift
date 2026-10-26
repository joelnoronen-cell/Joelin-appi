import Foundation

/// A plan understood from free text such as "Dentist Friday at 3pm".
struct ParsedPlan: Equatable {
    var title: String
    var start: Date
    var hasTime: Bool
    var durationMinutes: Int
    var category: PlanCategory
    var priority: PlanPriority
}

/// What the user wants from Jarvis.
enum JarvisIntent: Equatable {
    case add(ParsedPlan)
    case dayBriefing(Date)
    case weekBriefing(Date)
    case freeTime(Date)
    case setName(String)
    case empty
}

/// A small, deterministic natural-language parser for plans and questions.
///
/// Understands things like:
/// - "Gym tomorrow at 7am for 1h"
/// - "Team meeting friday 10:30-11:15 #work"
/// - "Call mom tonight", "Dentist next tuesday 3pm!"
/// - "Pay rent oct 31", "Study physics in 2 days", "Coffee in 30 min"
/// - "What's on tomorrow?", "Am I free friday afternoon?", "Brief me on my week"
struct PlanParser {
    var calendar: Calendar = .current
    var now: Date = .now

    // MARK: - Public API

    func interpret(_ input: String) -> JarvisIntent {
        let text = Self.clean(input)
        guard !text.isEmpty else { return .empty }
        let lower = text.lowercased()

        if let name = Self.name(from: lower, original: text) {
            return .setName(name)
        }

        if Self.isQuestion(lower) {
            let analysis = analyze(text)
            let day = analysis.day.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: now)
            let words = Set(Self.tokens(of: lower).map(Self.normalize))
            if !words.isDisjoint(with: ["free", "available", "availability", "busy", "gap", "gaps"]) {
                return .freeTime(day)
            }
            if words.contains("week") && words.isDisjoint(with: Self.weekdays.keys) {
                return .weekBriefing(day)
            }
            return .dayBriefing(day)
        }

        guard let plan = parse(text) else { return .empty }
        return .add(plan)
    }

    func parse(_ input: String) -> ParsedPlan? {
        let text = Self.clean(input)
        guard !text.isEmpty else { return nil }
        let a = analyze(text)
        let today = calendar.startOfDay(for: now)

        let category = a.category ?? Self.guessCategory(in: a.titleWords.joined(separator: " ")) ?? .personal
        // Work and study rarely happen at 9 PM: "standup at 9" means the morning.
        let prefersDaytime = category == .work || category == .study

        var start: Date
        var hasTime = true

        if let absolute = a.absolute {
            start = absolute
        } else {
            let baseDay = a.day ?? today
            if let time = a.time {
                let hour = time.ambiguous
                    ? resolveAmbiguous(hour: time.hour, minute: time.minute, period: a.period, day: baseDay, explicitDay: a.day != nil, prefersDaytime: prefersDaytime)
                    : time.hour
                start = at(baseDay, hour: hour, minute: time.minute)
                if a.day == nil && start <= now {
                    start = calendar.date(byAdding: .day, value: 1, to: start) ?? start
                }
            } else if let period = a.period {
                start = at(baseDay, hour: period, minute: 0)
                if a.day == nil && start <= now {
                    start = calendar.date(byAdding: .day, value: 1, to: start) ?? start
                }
            } else {
                start = baseDay
                hasTime = false
            }
        }

        var duration = a.duration ?? category.defaultDuration
        if a.duration == nil, let end = a.endTime, hasTime {
            let endHour = Self.alignEnd(hour: end.hour, ambiguous: end.ambiguous, after: calendar.component(.hour, from: start))
            let endDate = at(calendar.startOfDay(for: start), hour: endHour, minute: end.minute)
            var minutes = Int(endDate.timeIntervalSince(start) / 60)
            if minutes <= 0 { minutes += 24 * 60 }
            if minutes > 0 && minutes <= 16 * 60 { duration = minutes }
        }

        var title = Self.makeTitle(from: a.titleWords)
        if title.isEmpty { title = "New plan" }

        return ParsedPlan(
            title: title,
            start: start,
            hasTime: hasTime,
            durationMinutes: max(duration, 5),
            category: category,
            priority: a.priority
        )
    }

    /// Best-guess category from keywords in a title, e.g. "gym" → health.
    static func guessCategory(in text: String) -> PlanCategory? {
        let words = tokens(of: text.lowercased()).map { word -> String in
            var w = normalize(word)
            if w.hasSuffix("'s") { w.removeLast(2) }
            return w
        }
        var best: (category: PlanCategory, score: Int)?
        for (category, keywords) in categoryKeywords {
            let score = words.filter { keywords.contains($0) }.count
            if score > 0 && score > (best?.score ?? 0) {
                best = (category, score)
            }
        }
        return best?.category
    }

    // MARK: - Analysis

    private struct ClockTime {
        var hour: Int
        var minute: Int
        var ambiguous: Bool
    }

    private struct Analysis {
        var day: Date?
        var time: ClockTime?
        var endTime: ClockTime?
        var period: Int?
        var absolute: Date?
        var duration: Int?
        var category: PlanCategory?
        var priority: PlanPriority = .normal
        var titleWords: [String] = []
    }

    private func analyze(_ text: String) -> Analysis {
        var a = Analysis()
        let body = Self.stripCommandPrefix(text)
        let originals = Self.tokens(of: body)
        let words = originals.map(Self.normalize)
        var used = Array(repeating: false, count: words.count)
        let today = calendar.startOfDay(for: now)

        func word(_ index: Int) -> String? {
            guard index >= 0, index < words.count, !used[index] else { return nil }
            return words[index]
        }
        func consume(_ indices: Int...) {
            for index in indices where index >= 0 && index < used.count { used[index] = true }
        }
        func isRangeConnector(_ index: Int) -> Bool {
            guard let w = word(index) else { return false }
            return Self.rangeConnectors.contains(w) || Self.rangeConnectors.contains(originals[index])
        }

        var i = 0
        while i < words.count {
            guard let w = word(i) else { i += 1; continue }
            if originals[i].hasSuffix("!") { a.priority = .high }

            // Punctuation-only tokens: "!" means important, the rest is noise.
            if w.isEmpty {
                if originals[i].contains("!") { a.priority = .high }
                if !Self.rangeConnectors.contains(originals[i]) { consume(i) }
                i += 1
                continue
            }

            // Hashtags: #work, #health, …
            if w.hasPrefix("#"), let category = PlanCategory(rawValue: String(w.dropFirst())) {
                a.category = category
                consume(i)
                i += 1
                continue
            }

            if ["urgent", "important", "asap", "!important", "#important"].contains(w) {
                a.priority = .high
                consume(i)
                i += 1
                continue
            }
            if w == "high", word(i + 1) == "priority" {
                a.priority = .high
                consume(i, i + 1)
                i += 2
                continue
            }

            // Relative days.
            if w == "day", word(i + 1) == "after", word(i + 2) == "tomorrow" {
                a.day = calendar.date(byAdding: .day, value: 2, to: today)
                consume(i, i + 1, i + 2)
                i += 3
                continue
            }
            if w == "today" {
                a.day = today
                consume(i)
                i += 1
                continue
            }
            if w == "tonight" {
                if a.day == nil { a.day = today }
                a.period = 20
                consume(i)
                i += 1
                continue
            }
            if ["tomorrow", "tmrw", "tmr", "tomorow", "tommorow", "tommorrow"].contains(w) {
                a.day = calendar.date(byAdding: .day, value: 1, to: today)
                consume(i)
                i += 1
                continue
            }

            // "next friday", "next week", "this weekend", "friday".
            if w == "next" || w == "this", let target = word(i + 1) {
                if let weekday = Self.weekdays[target] {
                    a.day = w == "next" ? nextWeek(weekday: weekday) : upcoming(weekday: weekday)
                    consume(i, i + 1)
                    i += 2
                    continue
                }
                if target == "week" && w == "next" {
                    let thisWeek = calendar.startOfWeek(for: today)
                    a.day = calendar.date(byAdding: .day, value: 7, to: thisWeek)
                    consume(i, i + 1)
                    i += 2
                    continue
                }
                if target == "weekend" {
                    let saturday = upcoming(weekday: 7)
                    a.day = w == "next" && calendar.isDate(saturday, equalTo: today, toGranularity: .weekOfYear)
                        ? calendar.date(byAdding: .day, value: 7, to: saturday)
                        : saturday
                    consume(i, i + 1)
                    i += 2
                    continue
                }
                if let period = Self.periods[target] {
                    if a.day == nil { a.day = today }
                    a.period = period
                    consume(i, i + 1)
                    i += 2
                    continue
                }
            }
            if let weekday = Self.weekdays[w] {
                a.day = upcoming(weekday: weekday)
                consume(i)
                i += 1
                continue
            }
            if w == "weekend" {
                a.day = upcoming(weekday: 7)
                consume(i)
                i += 1
                continue
            }

            // Calendar dates: "oct 30", "october 30th", "30 oct", "30th of october".
            if let month = Self.months[w], let next = word(i + 1), let dayNumber = Self.dayNumber(next),
               let resolved = makeDate(month: month, day: dayNumber) {
                a.day = resolved
                consume(i, i + 1)
                i += 2
                continue
            }
            if let dayNumber = Self.dayNumber(w) {
                if let next = word(i + 1), let month = Self.months[next], let resolved = makeDate(month: month, day: dayNumber) {
                    a.day = resolved
                    consume(i, i + 1)
                    i += 2
                    continue
                }
                if word(i + 1) == "of", let next = word(i + 2), let month = Self.months[next],
                   let resolved = makeDate(month: month, day: dayNumber) {
                    a.day = resolved
                    consume(i, i + 1, i + 2)
                    i += 3
                    continue
                }
                // "on the 30th" – the next time that day of the month comes round.
                if Self.isOrdinal(w), let resolved = nextDate(dayOfMonth: dayNumber) {
                    a.day = resolved
                    consume(i)
                    i += 1
                    continue
                }
            }

            // "in 20 minutes", "in 2h", "in 3 days", "in half an hour".
            if w == "in", let offset = parseAmount(at: i + 1, word: word) {
                switch offset.unit {
                case .minutes:
                    a.absolute = roundedToMinute(now.addingTimeInterval(offset.value * 60))
                case .days:
                    a.day = calendar.date(byAdding: .day, value: Int(offset.value.rounded()), to: today)
                }
                consume(i)
                for index in (i + 1)..<(i + 1 + offset.length) { consume(index) }
                i += 1 + offset.length
                continue
            }

            // "for 45 min", "for an hour", "for 1h30".
            if w == "for", let length = parseAmount(at: i + 1, word: word), length.unit == .minutes {
                a.duration = Int(length.value.rounded())
                consume(i)
                for index in (i + 1)..<(i + 1 + length.length) { consume(index) }
                i += 1 + length.length
                continue
            }

            // Times and time ranges.
            if w == "noon" || w == "midday" {
                a.time = ClockTime(hour: 12, minute: 0, ambiguous: false)
                consume(i)
                i += 1
                continue
            }
            if w == "midnight" {
                a.time = ClockTime(hour: 23, minute: 59, ambiguous: false)
                consume(i)
                i += 1
                continue
            }
            if w.contains("-"), a.time == nil, let range = Self.timeRange(w) {
                a.time = range.start
                a.endTime = range.end
                consume(i)
                i += 1
                continue
            }
            let previous = i > 0 ? words[i - 1] : ""
            var allowBare = Self.timeConnectors.contains(previous)
            if !allowBare, isRangeConnector(i + 1), let endToken = word(i + 2),
               Self.clockTime(endToken, next: word(i + 3), allowBare: false) != nil {
                allowBare = true // "7 to 8am"
            }
            if a.time == nil, let parsed = Self.clockTime(w, next: word(i + 1), allowBare: allowBare) {
                a.time = parsed.time
                consume(i)
                var cursor = i + 1
                if parsed.usedNext {
                    consume(cursor)
                    cursor += 1
                }
                // "3 to 5pm", "10:00 - 11:30", "9 until 11"
                if isRangeConnector(cursor),
                   let endToken = word(cursor + 1),
                   let end = Self.clockTime(endToken, next: word(cursor + 2), allowBare: true) {
                    var start = parsed.time
                    if start.ambiguous, !end.time.ambiguous {
                        start = Self.inheritMeridiem(start: start, end: end.time)
                        a.time = start
                    }
                    a.endTime = end.time
                    consume(cursor, cursor + 1)
                    cursor += 2
                    if end.usedNext {
                        consume(cursor)
                        cursor += 1
                    }
                }
                i = cursor
                continue
            }

            // Parts of the day: "morning", "this evening", "in the afternoon".
            if let period = Self.periods[w] {
                a.period = period
                consume(i)
                i += 1
                continue
            }

            // Bare durations: "45min", "2 hours".
            if previous != "in", let length = parseAmount(at: i, word: word), length.unit == .minutes {
                a.duration = Int(length.value.rounded())
                for index in i..<(i + length.length) { consume(index) }
                i += length.length
                continue
            }

            i += 1
        }

        // Swallow connector words glued to the parts we understood:
        // "Lunch with Sam at noon on friday" → "Lunch with Sam".
        var changed = true
        while changed {
            changed = false
            for index in words.indices where !used[index] && Self.connectors.contains(words[index]) {
                let nextUsed = index + 1 < used.count && used[index + 1]
                if nextUsed {
                    used[index] = true
                    changed = true
                }
            }
        }

        a.titleWords = originals.indices
            .filter { !used[$0] }
            .map { originals[$0] }
        return a
    }

    // MARK: - Dates

    private func at(_ day: Date, hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: min(max(hour, 0), 23), minute: min(max(minute, 0), 59), second: 0, of: day) ?? day
    }

    private func roundedToMinute(_ date: Date) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: parts) ?? date
    }

    /// The next `weekday` (1 = Sunday … 7 = Saturday), today included.
    private func upcoming(weekday: Int) -> Date {
        let today = calendar.startOfDay(for: now)
        let current = calendar.component(.weekday, from: today)
        var delta = weekday - current
        if delta < 0 { delta += 7 }
        return calendar.date(byAdding: .day, value: delta, to: today) ?? today
    }

    /// `weekday` within next calendar week.
    private func nextWeek(weekday: Int) -> Date {
        let today = calendar.startOfDay(for: now)
        let thisWeek = calendar.startOfWeek(for: today)
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: thisWeek) ?? today
        for offset in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: nextWeekStart),
               calendar.component(.weekday, from: day) == weekday {
                return day
            }
        }
        return calendar.date(byAdding: .day, value: 7, to: upcoming(weekday: weekday)) ?? today
    }

    private func makeDate(month: Int, day: Int) -> Date? {
        let today = calendar.startOfDay(for: now)
        var parts = DateComponents()
        parts.year = calendar.component(.year, from: today)
        parts.month = month
        parts.day = day
        guard var result = calendar.date(from: parts),
              calendar.component(.month, from: result) == month else { return nil }
        if result < today, let nextYear = calendar.date(byAdding: .year, value: 1, to: result) {
            result = nextYear
        }
        return result
    }

    private func nextDate(dayOfMonth day: Int) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let thisMonth = calendar.dateInterval(of: .month, for: today)?.start else { return nil }
        for offset in 0..<3 {
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: thisMonth),
                  let candidate = calendar.date(byAdding: .day, value: day - 1, to: monthStart),
                  calendar.isDate(candidate, equalTo: monthStart, toGranularity: .month) else { continue }
            if candidate >= today { return candidate }
        }
        return nil
    }

    /// Picks AM or PM for times like "at 7" based on what's still ahead.
    private func resolveAmbiguous(hour: Int, minute: Int, period: Int?, day: Date, explicitDay: Bool, prefersDaytime: Bool) -> Int {
        if let period {
            if period >= 12 && hour < 12 { return hour + 12 }
            return hour
        }
        let candidates: [Int]
        switch hour {
        case 12: candidates = [12]
        case 1...6: candidates = [hour + 12]
        case 7...11 where prefersDaytime: candidates = [hour]
        default: candidates = [hour, hour + 12]
        }
        if !explicitDay || calendar.isDate(day, inSameDayAs: now) {
            for candidate in candidates where at(day, hour: candidate, minute: minute) > now {
                return candidate
            }
        }
        return candidates[0]
    }

    // MARK: - Amounts ("2 hours", "half an hour", "3 days")

    private enum AmountUnit { case minutes, days }

    private struct Amount {
        var value: Double
        var unit: AmountUnit
        var length: Int
    }

    private func parseAmount(at index: Int, word: (Int) -> String?) -> Amount? {
        guard let first = word(index) else { return nil }

        if let minutes = Self.compactMinutes(first) {
            return Amount(value: Double(minutes), unit: .minutes, length: 1)
        }
        if first == "half", let article = word(index + 1), article == "an" || article == "a",
           let unit = word(index + 2), Self.hourUnits.contains(unit) {
            return Amount(value: 30, unit: .minutes, length: 3)
        }
        guard let value = Self.number(first), let unitWord = word(index + 1) else { return nil }
        if Self.hourUnits.contains(unitWord) {
            return Amount(value: value * 60, unit: .minutes, length: 2)
        }
        if Self.minuteUnits.contains(unitWord) {
            return Amount(value: value, unit: .minutes, length: 2)
        }
        if ["day", "days"].contains(unitWord) {
            return Amount(value: value, unit: .days, length: 2)
        }
        if ["week", "weeks"].contains(unitWord) {
            return Amount(value: value * 7, unit: .days, length: 2)
        }
        return nil
    }

    // MARK: - Token helpers

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(of text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Lowercased token without surrounding punctuation ("Friday," → "friday").
    static func normalize(_ token: String) -> String {
        let trimSet = CharacterSet(charactersIn: ",;:!?\"()[]{}…").union(.whitespaces)
        var word = token.lowercased().trimmingCharacters(in: trimSet)
        while word.hasSuffix(".") { word.removeLast() }
        while word.hasPrefix("-") || word.hasPrefix("–") { word.removeFirst() }
        while word.hasSuffix("-") || word.hasSuffix("–") { word.removeLast() }
        return word
    }

    private static func stripCommandPrefix(_ text: String) -> String {
        let lower = text.lowercased()
        for prefix in commandPrefixes where lower.hasPrefix(prefix) {
            let rest = String(text.dropFirst(prefix.count))
            if !rest.trimmingCharacters(in: .whitespaces).isEmpty { return rest }
        }
        return text
    }

    private static func makeTitle(from words: [String]) -> String {
        var parts = words.map { $0.replacingOccurrences(of: "!", with: "") }.filter { !$0.isEmpty }
        while let first = parts.first, connectors.contains(normalize(first)) { parts.removeFirst() }
        while let last = parts.last, connectors.contains(normalize(last)) || normalize(last).isEmpty { parts.removeLast() }
        var title = parts.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–").union(.whitespaces))
        if let first = title.first {
            title = first.uppercased() + title.dropFirst()
        }
        return title
    }

    private static func number(_ word: String) -> Double? {
        if let value = Double(word.replacingOccurrences(of: ",", with: ".")), value > 0 { return value }
        return numberWords[word]
    }

    /// "30m", "45min", "2h", "1.5hrs", "1h30" → minutes.
    static func compactMinutes(_ token: String) -> Int? {
        let chars = Array(token)
        var index = 0
        var total = 0.0
        var sawUnit = false
        while index < chars.count {
            var digits = ""
            while index < chars.count, chars[index].isASCII, chars[index].isNumber || chars[index] == "." {
                digits.append(chars[index])
                index += 1
            }
            var unit = ""
            while index < chars.count, chars[index].isLetter {
                unit.append(chars[index])
                index += 1
            }
            guard let value = Double(digits) else { return nil }
            if unit.isEmpty {
                // Trailing minutes in "1h30".
                guard sawUnit, index == chars.count else { return nil }
                total += value
            } else if hourUnits.contains(unit) {
                total += value * 60
                sawUnit = true
            } else if minuteUnits.contains(unit) || unit == "m" {
                total += value
                sawUnit = true
            } else {
                return nil
            }
            if index < chars.count, !chars[index].isNumber { return nil }
        }
        guard sawUnit, total > 0 else { return nil }
        return Int(total.rounded())
    }

    private static func dayNumber(_ word: String) -> Int? {
        var digits = word
        for suffix in ["st", "nd", "rd", "th"] where digits.hasSuffix(suffix) {
            digits.removeLast(suffix.count)
            break
        }
        guard let value = Int(digits), (1...31).contains(value) else { return nil }
        return value
    }

    private static func isOrdinal(_ word: String) -> Bool {
        ["st", "nd", "rd", "th"].contains { word.hasSuffix($0) } && Int(word.dropLast(2)) != nil
    }

    private enum Meridiem { case am, pm }

    private static func meridiem(_ word: String?) -> Meridiem? {
        guard let word else { return nil }
        switch word {
        case "am", "a.m", "a": return .am
        case "pm", "p.m", "p": return .pm
        default: return nil
        }
    }

    /// Parses "7", "7pm", "7:30", "7.30pm", "19:30". Bare numbers ("7") only
    /// count as a time when `allowBare` is set or a meridiem follows.
    private static func clockTime(_ token: String, next: String?, allowBare: Bool) -> (time: ClockTime, usedNext: Bool)? {
        var body = token
        var meridiem: Meridiem?
        let suffixes: [(String, Meridiem)] = [("a.m", .am), ("p.m", .pm), ("am", .am), ("pm", .pm), ("a", .am), ("p", .pm)]
        for (suffix, value) in suffixes where body.count > suffix.count && body.hasSuffix(suffix) {
            body.removeLast(suffix.count)
            meridiem = value
            break
        }
        var usedNext = false
        if meridiem == nil, let following = self.meridiem(next), next != "a" {
            meridiem = following
            usedNext = true
        }

        let parts = body.split(omittingEmptySubsequences: false) { $0 == ":" || $0 == "." }
        guard parts.count == 1 || parts.count == 2,
              parts[0].count <= 2,
              let hour = Int(parts[0]) else { return nil }
        var minute = 0
        if parts.count == 2 {
            guard parts[1].count == 2, let value = Int(parts[1]), (0..<60).contains(value) else { return nil }
            minute = value
        }
        let hasSeparator = parts.count == 2

        guard meridiem != nil || hasSeparator || allowBare else { return nil }

        switch meridiem {
        case .am:
            guard (1...12).contains(hour) else { return nil }
            return (ClockTime(hour: hour == 12 ? 0 : hour, minute: minute, ambiguous: false), usedNext)
        case .pm:
            guard (1...12).contains(hour) else { return nil }
            return (ClockTime(hour: hour == 12 ? 12 : hour + 12, minute: minute, ambiguous: false), usedNext)
        case nil:
            guard (0...23).contains(hour) else { return nil }
            let twentyFourHour = hour == 0 || hour > 12 || parts[0].hasPrefix("0")
            return (ClockTime(hour: hour, minute: minute, ambiguous: !twentyFourHour), false)
        }
    }

    /// "3-5pm", "10:00-11:30", "9am-11am".
    private static func timeRange(_ token: String) -> (start: ClockTime, end: ClockTime)? {
        let sides = token.split(separator: "-", omittingEmptySubsequences: false)
        guard sides.count == 2,
              let end = clockTime(String(sides[1]), next: nil, allowBare: true),
              let start = clockTime(String(sides[0]), next: nil, allowBare: true) else { return nil }
        let resolvedStart = start.time.ambiguous && !end.time.ambiguous
            ? inheritMeridiem(start: start.time, end: end.time)
            : start.time
        return (resolvedStart, end.time)
    }

    /// In "3-5pm" the start takes the end's meridiem unless that would put
    /// it after the end ("11-1pm" → 11 AM).
    private static func inheritMeridiem(start: ClockTime, end: ClockTime) -> ClockTime {
        var result = start
        result.ambiguous = false
        if end.hour >= 12 {
            let pm = start.hour == 12 ? 12 : start.hour + 12
            result.hour = pm <= end.hour ? pm : start.hour
        }
        return result
    }

    private static func alignEnd(hour: Int, ambiguous: Bool, after startHour: Int) -> Int {
        guard ambiguous else { return hour }
        if hour <= startHour && hour + 12 <= 23 { return hour + 12 }
        return hour
    }

    // MARK: - Intent helpers

    private static func isQuestion(_ lower: String) -> Bool {
        if lower.hasSuffix("?") { return true }
        return questionStarters.contains { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ",") }
    }

    private static func name(from lower: String, original: String) -> String? {
        for prefix in ["call me ", "my name is ", "my name's "] where lower.hasPrefix(prefix) {
            let rest = String(original.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            let parts = rest.split(separator: " ")
            guard (1...3).contains(parts.count),
                  rest.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" }) else { return nil }
            let blocked: Set<String> = ["back", "later", "tomorrow", "today", "tonight", "when", "at", "after", "before", "in", "on", "if", "soon", "maybe"]
            guard !parts.contains(where: { blocked.contains($0.lowercased()) }) else { return nil }
            return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        return nil
    }

    // MARK: - Vocabulary

    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7,
    ]

    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3,
        "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
        "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9,
        "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
    ]

    /// Hour each part of the day maps to.
    private static let periods: [String: Int] = [
        "morning": 9, "afternoon": 14, "evening": 18, "night": 20, "lunchtime": 12,
    ]

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "fifteen": 15,
        "twenty": 20, "thirty": 30, "forty": 40, "fortyfive": 45, "ninety": 90,
        "couple": 2, "few": 3,
    ]

    private static let hourUnits: Set<String> = ["h", "hr", "hrs", "hour", "hours"]
    private static let minuteUnits: Set<String> = ["min", "mins", "minute", "minutes"]

    /// Words that may precede a bare number to make it a time ("at 7").
    private static let timeConnectors: Set<String> = ["at", "@", "around", "by", "from", "about", "til", "till", "until"]

    private static let rangeConnectors: Set<String> = ["to", "until", "till", "til", "-", "–"]

    /// Glue words dropped from the title when they lead into a date or time.
    private static let connectors: Set<String> = [
        "at", "on", "by", "for", "from", "in", "the", "this", "next", "around", "about",
        "until", "till", "til", "to", "due", "@", "of", "starting", "-", "–",
    ]

    private static let commandPrefixes = [
        "remind me to ", "remember to ", "don't forget to ", "dont forget to ",
        "i need to ", "i have to ", "i've got to ", "ive got to ", "i've got a ", "i've got an ",
        "i have a ", "i have an ", "i got a ", "need to ", "please add ", "please ",
        "add ", "schedule ", "create ", "remind me ",
    ]

    private static let questionStarters = [
        "what", "what's", "whats", "how's", "hows", "how is", "how does", "how do", "how many",
        "when am i", "when's", "whens", "show me", "show my", "brief me", "briefing",
        "anything", "do i", "am i", "is my", "is there", "are there", "tell me", "give me",
        "summary", "summarize", "summarise", "my day", "my week", "my schedule", "agenda",
        "what about", "which", "any plans", "status", "report", "update me", "where",
    ]

    private static let categoryKeywords: [(PlanCategory, Set<String>)] = [
        (.work, [
            "meeting", "meetings", "standup", "stand-up", "sync", "presentation", "client", "clients",
            "project", "deadline", "report", "email", "emails", "interview", "review", "office", "work",
            "demo", "pitch", "1:1", "1on1", "invoice", "deploy", "sprint", "retro", "planning", "boss",
            "manager", "team", "workshop", "conference", "slides", "proposal",
        ]),
        (.health, [
            "gym", "workout", "run", "running", "jog", "jogging", "yoga", "pilates", "doctor", "dentist",
            "therapy", "therapist", "physio", "swim", "swimming", "training", "walk", "hike", "bike",
            "cycling", "meditate", "meditation", "football", "soccer", "basketball", "tennis", "padel",
            "climbing", "stretch", "stretching", "checkup", "check-up", "hospital", "clinic", "sleep",
            "cardio", "legs", "lift", "lifting", "boxing", "spin",
        ]),
        (.study, [
            "study", "studying", "homework", "exam", "exams", "class", "lecture", "course", "learn",
            "learning", "revise", "revision", "assignment", "essay", "read", "reading", "school",
            "lesson", "lessons", "quiz", "test", "tutor", "practice", "thesis", "chapter", "research",
            "university", "uni", "college", "physics", "math", "maths", "chemistry", "biology", "history",
        ]),
        (.social, [
            "dinner", "lunch", "brunch", "breakfast", "party", "drinks", "coffee", "friends", "friend",
            "date", "birthday", "wedding", "mom", "mum", "dad", "family", "visit", "hangout", "bbq",
            "movie", "movies", "concert", "game", "games", "grandma", "grandpa", "sister", "brother",
            "girlfriend", "boyfriend", "wife", "husband", "kids", "festival", "club", "beer", "pub",
        ]),
        (.errands, [
            "buy", "groceries", "grocery", "shop", "shopping", "pick", "pickup", "laundry", "clean",
            "cleaning", "pay", "bank", "post", "return", "fix", "repair", "car", "pharmacy", "order",
            "renew", "bills", "bill", "rent", "trash", "dishes", "cook", "pack", "packing", "haircut",
            "barber", "mechanic", "taxes", "tax", "package", "parcel", "vacuum", "supermarket", "store",
        ]),
    ]
}
