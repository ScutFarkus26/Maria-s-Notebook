// RestoredWithSyncOffQuestion.swift
// Settings' question before turning iCloud sync on after the database-error
// screen restored a backup with sync off (`RestoredWithSyncOff`).

import SwiftUI

extension View {
    /// Turn On Anyway turns sync on and stops asking; Cancel leaves it off.
    func restoredWithSyncOffQuestion(isPresented: Binding<Bool>) -> some View {
        confirmationDialog(
            RestoredWithSyncOff.questionTitle,
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button(RestoredWithSyncOff.turnOnAnywayLabel) {
                RestoredWithSyncOff.turnOnAnyway(in: .standard)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(RestoredWithSyncOff.question)
        }
    }
}
