//
//  Log.swift
//  AdSilencer
//
//  The app log.
//

import Foundation
import OSLog

enum Log {
    static let spotify = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ensarbaba.AdSilencer",
        category: "Spotify"
    )
}
