//
//  Item.swift
//  VoiceInput
//
//  Created by Tenyi on 2026/2/14.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
