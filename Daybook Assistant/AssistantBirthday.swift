import Foundation

/// A child's birthday on the day on screen, so the assistant can greet them at
/// the door. A child born in June, July or August has their birthday when
/// school is out, so they get a half-birthday six months on instead, as
/// Montessori classrooms usually celebrate them.
enum AssistantBirthday: Equatable {
    case birthday
    case halfBirthday

    /// "Birthday" or "Half-birthday", for the menu header and VoiceOver.
    var title: String {
        switch self {
        case .birthday: return "Birthday"
        case .halfBirthday: return "Half-birthday"
        }
    }

    var symbol: String {
        switch self {
        case .birthday: return "birthday.cake.fill"
        case .halfBirthday: return "birthday.cake"
        }
    }

    /// Summer birthdays, celebrated as half-birthdays.
    private static let summerMonths: Set<Int> = [6, 7, 8]

    /// The child's birthday or half-birthday on `day`, if it is one.
    ///
    /// A birthday that was never entered holds the day the child was added
    /// (`CDStudent`'s initializer stamps `Date()`), which would put a cake on
    /// that date every year; a child under three can't be in the class, so
    /// those are left out. A Feb 29 birthday is kept on Feb 28 in other years.
    static func on(_ day: Date, birthday: Date?, calendar: Calendar = .current) -> AssistantBirthday? {
        guard let birthday,
              let age = calendar.dateComponents([.year], from: calendar.startOfDay(for: birthday), to: day).year,
              (3...21).contains(age)
        else { return nil }
        let born = calendar.dateComponents([.month, .day], from: birthday)
        guard let month = born.month, let dayOfMonth = born.day else { return nil }
        let year = calendar.component(.year, from: day)

        if let anniversary = anniversary(month: month, day: dayOfMonth, year: year, calendar: calendar),
           calendar.isDate(anniversary, inSameDayAs: day) {
            return .birthday
        }
        guard summerMonths.contains(month) else { return nil }
        // Last year's summer birthday lands in this year's winter.
        for birthdayYear in [year - 1, year] {
            if let anniversary = anniversary(month: month, day: dayOfMonth, year: birthdayYear, calendar: calendar),
               let half = calendar.date(byAdding: .month, value: 6, to: anniversary),
               calendar.isDate(half, inSameDayAs: day) {
                return .halfBirthday
            }
        }
        return nil
    }

    /// `month`/`day` in `year`, with Feb 29 on Feb 28 when `year` has none.
    private static func anniversary(month: Int, day: Int, year: Int, calendar: Calendar) -> Date? {
        let first = DateComponents(year: year, month: month, day: 1)
        guard let monthStart = calendar.date(from: first),
              let days = calendar.range(of: .day, in: .month, for: monthStart)?.count
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: min(day, days)))
    }
}
