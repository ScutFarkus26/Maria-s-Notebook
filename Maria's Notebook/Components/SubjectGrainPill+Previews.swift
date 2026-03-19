// SubjectGrainPill+Previews.swift

import SwiftUI

// MARK: - Preview

#Preview("Subject Grain Pills") {
    let subjects = [
        ("Math", "Golden Bead Exchange"),
        ("Science", "Parts of a Flower"),
        ("History", "Timeline of Life"),
        ("Language", "Moveable Alphabet"),
        ("Botany", "Leaf Shapes"),
        ("Music", "Bells — Grading"),
        ("Art", "Color Wheel"),
        ("Geography", "Continent Globe"),
        ("Practical Life", "Pouring Exercise"),
        ("Sensorial", "Pink Tower"),
        ("Grace & Courtesy", "Greeting a Visitor"),
        ("Geometry", "Metal Insets"),
        ("Writing", "Sandpaper Letters"),
        ("Zoology", "Parts of a Fish"),
        ("Reading", "Phonogram Booklets"),
        ("Culture", "Fundamental Needs")
    ]

    ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subject Grain Pills")
                .font(AppTheme.ScaledFont.titleMedium)
                .padding(.bottom, 4)

            ForEach(subjects, id: \.0) { subject, lesson in
                SubjectGrainPill(subject: subject) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AppColors.color(forSubject: subject))
                            .frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lesson)
                                .font(AppTheme.ScaledFont.captionSemibold)
                                .foregroundStyle(.primary)
                            Text(subject)
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding()
    }
}

#Preview("Pattern Comparison") {
    let subjects = [
        "Math", "Science", "History", "Language",
        "Botany", "Music", "Art", "Geography",
        "Practical Life", "Sensorial", "Grace & Courtesy", "Geometry"
    ]

    ScrollView {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(subjects, id: \.self) { subject in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .frame(height: 80)
                        .overlay {
                            SubjectGrainBackground(subject: subject)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.color(forSubject: subject).opacity(0.2), lineWidth: 1)
                        }

                    Text(subject)
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
