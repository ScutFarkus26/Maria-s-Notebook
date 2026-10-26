// HebrewBirthdayViews.swift
// The child's Hebrew birthday on the student page: the row under Birthday,
// and the "Born after sunset" switch the edit form and Add Student share
// (docs/Plans/Plan - Hebrew birthdays.md).

import SwiftUI

// MARK: - HebrewBirthdayInfoRow

/// "14 Adar II 5784 · י״ד באדר ב׳ ה׳תשפ״ד" on one line where it fits; on a
/// phone the English and the Hebrew take a line each, so the Hebrew never
/// breaks in the middle.
struct HebrewBirthdayInfoRow: View {
    let birthday: HebrewBirthday

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Chosen when its unwrapped width fits.
            InfoRowView(icon: Self.icon, title: Self.title, value: birthday.display)
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(Self.title)
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: Self.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                .labelStyle(.titleAndIcon)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(birthday.english)
                    Text(birthday.hebrew)
                }
                .font(AppTheme.ScaledFont.titleSmall)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(Self.title))
            .accessibilityValue(Text(birthday.display))
        }
    }

    private static let title = "Hebrew Birthday"
    private static let icon = "moon.stars"
}

// MARK: - BornAfterSunsetToggle

/// The "Born after sunset" switch under a birthday picker, with the Hebrew
/// birthday it gives, so flipping it shows the date move a day.
struct BornAfterSunsetToggle: View {
    @Binding var isOn: Bool
    /// Nil while no birthday has been chosen, so the note names no date.
    let birthday: Date?

    private var hebrewBirthday: String? {
        guard let birthday else { return nil }
        return HebrewBirthday(birthday: birthday, bornAfterSunset: isOn)?.english
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Born after sunset", isOn: $isOn)
            Group {
                if let hebrewBirthday {
                    Text("A Hebrew date begins at sunset. Hebrew birthday: \(hebrewBirthday).")
                } else {
                    Text("A Hebrew date begins at sunset.")
                }
            }
            .font(AppTheme.ScaledFont.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
