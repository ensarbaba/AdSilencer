//
//  SavedVolumeStore.swift
//  AdSilencer
//
//  Storage for a volume that must survive an app stop.
//

import Foundation

protocol SavedVolumeStore: Sendable {
    func load() -> Int?
    func save(_ volume: Int?)
}

final class UserDefaultsSavedVolumeStore: SavedVolumeStore, @unchecked Sendable {
    private static let key = "savedSpotifyVolume"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> Int? {
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        return defaults.integer(forKey: Self.key)
    }

    func save(_ volume: Int?) {
        if let volume {
            defaults.set(volume, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
