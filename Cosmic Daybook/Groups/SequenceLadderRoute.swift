//
//  SequenceLadderRoute.swift
//  Cosmic Daybook
//
//  What a Groups card's "area · sequence" breadcrumb pushes: one sub-area's
//  ladder. `GroupsView` registers the destination (`SequenceLadderView`).
//

import Foundation

struct SequenceLadderRoute: Hashable {
    let area: String
    let sequence: String
}
