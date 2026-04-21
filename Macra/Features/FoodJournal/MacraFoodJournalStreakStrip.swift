import SwiftUI

struct MacraFoodJournalLoggingStats: Hashable {
    let currentStreak: Int
    let longestStreak: Int
    let weeklyCompletion: [Bool]
    let referenceDate: Date

    init(loggedDates: Set<Date>, referenceDate: Date) {
        let calendar = Calendar.current
        let startOfReference = calendar.startOfDay(for: referenceDate)

        var current = 0
        var cursor = startOfReference
        while loggedDates.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        if current == 0,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfReference),
           loggedDates.contains(yesterday) {
            var back = yesterday
            while loggedDates.contains(back) {
                current += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: back) else { break }
                back = previous
            }
        }

        let sortedDates = loggedDates.sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for date in sortedDates {
            if let previous,
               let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(expected, inSameDayAs: date) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = date
        }

        var weekdayIndex = calendar.component(.weekday, from: startOfReference)
        let shift = ((weekdayIndex - calendar.firstWeekday) + 7) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -shift, to: startOfReference) else {
            self.currentStreak = current
            self.longestStreak = longest
            self.weeklyCompletion = Array(repeating: false, count: 7)
            self.referenceDate = referenceDate
            return
        }

        var weekly: [Bool] = []
        for offset in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: weekStart) {
                weekly.append(loggedDates.contains(calendar.startOfDay(for: day)))
            } else {
                weekly.append(false)
            }
        }

        _ = weekdayIndex
        self.currentStreak = current
        self.longestStreak = max(longest, current)
        self.weeklyCompletion = weekly
        self.referenceDate = referenceDate
    }
}

struct MacraFoodJournalStreakStrip: View {
    let stats: MacraFoodJournalLoggingStats

    private var weekdayLabels: [String] {
        let calendar = Calendar.current
        let base = calendar.firstWeekday - 1
        let short = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { offset in
            let idx = (base + offset) % 7
            let label = short[idx]
            return String(label.prefix(1))
        }
    }

    private var todayIndex: Int {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: stats.referenceDate)
        return ((weekday - calendar.firstWeekday) + 7) % 7
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                streakPill(
                    label: "Current",
                    value: "\(stats.currentStreak)",
                    caption: stats.currentStreak == 1 ? "day" : "days",
                    icon: "flame.fill",
                    tint: MacraFoodJournalTheme.accent3
                )
                streakPill(
                    label: "Longest",
                    value: "\(stats.longestStreak)",
                    caption: stats.longestStreak == 1 ? "day" : "days",
                    icon: "rosette",
                    tint: MacraFoodJournalTheme.accent
                )
            }

            VStack(spacing: 8) {
                HStack {
                    Text("This week")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                    Spacer()
                    Text("\(stats.weeklyCompletion.filter { $0 }.count) / 7 days")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(MacraFoodJournalTheme.textSoft)
                }
                HStack(spacing: 10) {
                    ForEach(0..<7, id: \.self) { index in
                        dayDot(
                            label: weekdayLabels[index],
                            isComplete: stats.weeklyCompletion[index],
                            isToday: index == todayIndex,
                            isFuture: index > todayIndex
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(MacraFoodJournalTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func streakPill(label: String, value: String, caption: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
                HStack(spacing: 4) {
                    Text(value)
                        .font(.title3.weight(.bold))
                        .foregroundColor(MacraFoodJournalTheme.text)
                    Text(caption)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(MacraFoodJournalTheme.textSoft)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(tint.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func dayDot(label: String, isComplete: Bool, isToday: Bool, isFuture: Bool) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
            ZStack {
                Circle()
                    .strokeBorder(
                        isToday ? MacraFoodJournalTheme.accent : Color.white.opacity(0.14),
                        lineWidth: isToday ? 2 : 1
                    )
                    .frame(width: 26, height: 26)
                if isComplete {
                    Circle()
                        .fill(MacraFoodJournalTheme.accent)
                        .frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.black)
                } else if isFuture {
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 20, height: 20)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 20, height: 20)
                }
            }
        }
    }
}
