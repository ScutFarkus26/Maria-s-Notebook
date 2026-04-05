// DevelopmentalTraitsViewModel.swift
// ViewModel for per-student developmental characteristics timeline.
// Queries Notes tagged with developmental traits and computes patterns.

import Foundation
import CoreData
import SwiftUI

@Observable
@MainActor
final class DevelopmentalTraitsViewModel {
    // MARK: - Inputs

    var studentID: UUID?
    var timeRange: ObservationTimeRange = .quarter

    // MARK: - Outputs

    private(set) var traitCards: [DevelopmentalTraitCardData] = []
    private(set) var recentObservations: [TraitObservation] = []
    private(set) var totalTraitObservations: Int = 0
    private(set) var isLoading = false

    // MARK: - Load Data

    func loadData(context: NSManagedObjectContext) {
        guard let studentID else {
            traitCards = []
            recentObservations = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        let descriptor = { let r = CDNote.fetchRequest() as! NSFetchRequest<CDNote>; r.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)]; return r }()
        let allNotes = context.safeFetch(descriptor)
        let range = timeRange.dateRange(from: Date())
        let traitNotes = filterTraitNotes(from: allNotes, studentID: studentID, range: range)

        totalTraitObservations = traitNotes.count
        traitCards = buildTraitCards(from: traitNotes)
        recentObservations = buildRecentObservations(from: traitNotes)
    }

    // MARK: - Private Helpers

    private func filterTraitNotes(
        from allNotes: [CDNote],
        studentID: UUID,
        range: (start: Date, end: Date)
    ) -> [CDNote] {
        allNotes.filter { note in
            guard let createdAt = note.createdAt else { return false }
            let inRange = createdAt >= range.start && createdAt <= range.end
            guard inRange else { return false }
            switch note.scope {
            case .all:
                return false
            case .student(let id):
                return id == studentID
            case .students(let ids):
                return ids.contains(studentID)
            }
        }.filter { note in
            let tags = (note.tags as? [String]) ?? []
            return tags.contains { DevelopmentalCharacteristic.isCharacteristicTag($0) }
        }
    }

    private func buildTraitCards(from traitNotes: [CDNote]) -> [DevelopmentalTraitCardData] {
        var traitNotesMap: [DevelopmentalCharacteristic: [CDNote]] = [:]
        for note in traitNotes {
            for tag in (note.tags as? [String]) ?? [] {
                if let characteristic = DevelopmentalCharacteristic.from(tag: tag) {
                    traitNotesMap[characteristic, default: []].append(note)
                }
            }
        }
        return DevelopmentalCharacteristic.allCases.map { characteristic in
            let notes = traitNotesMap[characteristic] ?? []
            return DevelopmentalTraitCardData(
                characteristic: characteristic,
                observationCount: notes.count,
                mostRecentDate: notes.first?.createdAt
            )
        }
        .sorted { $0.observationCount > $1.observationCount }
    }

    private func buildRecentObservations(from traitNotes: [CDNote]) -> [TraitObservation] {
        traitNotes.prefix(20).map { note in
            let tags = (note.tags as? [String]) ?? []
            let traits = tags.compactMap { DevelopmentalCharacteristic.from(tag: $0) }
            return TraitObservation(
                id: note.id ?? UUID(),
                date: note.createdAt ?? Date(),
                bodyPreview: String(note.body.prefix(100)),
                traits: traits
            )
        }
    }
}

// MARK: - Supporting Types

struct DevelopmentalTraitCardData: Identifiable {
    let id = UUID()
    let characteristic: DevelopmentalCharacteristic
    let observationCount: Int
    let mostRecentDate: Date?
}

struct TraitObservation: Identifiable {
    let id: UUID
    let date: Date
    let bodyPreview: String
    let traits: [DevelopmentalCharacteristic]
}
