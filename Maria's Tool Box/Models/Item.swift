//
//  Item.swift
//  Maria's Toolbox
//
//  Created by Danny De Berry on 11/26/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
