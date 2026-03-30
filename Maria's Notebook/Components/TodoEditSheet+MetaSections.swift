// TodoEditSheet+MetaSections.swift
// Mood/reflection and location reminder sections.

import SwiftUI

extension TodoEditSheet {
    // MARK: - Mood & Reflection Section

    @ViewBuilder
    var moodReflectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mood & Reflection")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            // Mood selection
            VStack(alignment: .leading, spacing: 8) {
                Text("How are you feeling about this task?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                    ForEach(TodoMood.allCases, id: \.self) { mood in
                        Button {
                            if selectedMood == mood {
                                selectedMood = nil // Deselect if already selected
                            } else {
                                selectedMood = mood
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(mood.emoji)
                                    .font(.title2)
                                Text(mood.rawValue)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selectedMood == mood
                                    ? mood.color.opacity(UIConstants.OpacityConstants.moderate)
                                    : Color.primary.opacity(UIConstants.OpacityConstants.trace)
                            )
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        selectedMood == mood ? mood.color : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Reflection notes
            VStack(alignment: .leading, spacing: 8) {
                Text("Reflection Notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $reflectionNotes)
                    .font(AppTheme.ScaledFont.body)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                    .cornerRadius(8)
                    .scrollContentBackground(.hidden)

                Text("Personal thoughts, lessons learned, or context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Location Reminder Section

    @ViewBuilder
    var locationReminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Location Reminder")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Toggle("", isOn: $hasLocationReminder)
                    .labelsHidden()
            }

            if hasLocationReminder {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("Location name (e.g., School, Home)", text: $locationName)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            isShowingMapPicker = true
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 16))
                                .padding(8)
                                .background(Color.blue.opacity(UIConstants.OpacityConstants.light))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    if let lat = locationLatitude, let lon = locationLongitude {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.red)
                            Text(String(format: "%.4f, %.4f", lat, lon))
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                locationLatitude = nil
                                locationLongitude = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Toggle("Notify on arrival", isOn: $notifyOnEntry)
                        Spacer()
                    }

                    HStack {
                        Toggle("Notify on departure", isOn: $notifyOnExit)
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(UIConstants.OpacityConstants.subtle))
                .cornerRadius(10)
            } else {
                Text("Set a location-based reminder for this task")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $isShowingMapPicker) {
            TodoLocationPickerView(
                locationName: $locationName,
                latitude: $locationLatitude,
                longitude: $locationLongitude
            )
        }
    }
}
