//
//  SpotifyScripting.swift
//  NotchTune
//
//  ScriptingBridge declarations for the Spotify client.
//
//  Hand-written instead of the `sdp`-generated header. That header declares a
//  class that nothing defines, so Swift fails to link against it. Objective-C
//  compiles because the type is never checked.
//
//  Member names map to entries in Spotify's dictionary. Renaming one breaks
//  the lookup silently.
//

import AppKit
import ScriptingBridge

/// Player state values: four characters packed into an integer.
/// Declared as `Int` so an unrecognised value does not trap.
enum SpotifyPlayerStateCode {
    static let stopped = 0x6B50_5353 // 'kPSS'
    static let playing = 0x6B50_5350 // 'kPSP'
    static let paused = 0x6B50_5370 // 'kPSp'
}

@objc protocol SpotifyScriptingTrack {
    @objc optional var id: String { get }
    @objc optional var name: String { get }
}

@objc protocol SpotifyScriptingApplication {
    @objc optional var currentTrack: SpotifyScriptingTrack { get }
    @objc optional var playerState: Int { get }
    @objc optional var soundVolume: Int { get }

    /// Setter for `soundVolume`. Declared as a method because Swift cannot
    /// assign through an optional protocol property.
    @objc optional func setSoundVolume(_ volume: Int)
}

extension SBApplication: SpotifyScriptingApplication {}
