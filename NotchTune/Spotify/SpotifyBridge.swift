//
//  SpotifyBridge.swift
//  NotchTune
//
//  The only code that talks to Spotify. Everything else depends on
//  SpotifyControlling and can run against a fake.
//

import AppKit
import CoreServices
import ScriptingBridge

enum SpotifyPlayerState: Equatable {
    case stopped
    case playing
    case paused

    init(code: Int) {
        switch code {
        case SpotifyPlayerStateCode.playing: self = .playing
        case SpotifyPlayerStateCode.paused: self = .paused
        default: self = .stopped
        }
    }
}

/// Whether this app may send Apple events to Spotify.
enum SpotifyAccess: Equatable {
    /// Permitted, or already granted.
    case ok
    /// The user has never been asked. The first Apple event triggers the prompt.
    case undetermined
    /// The user denied it in System Settings > Privacy & Security > Automation.
    case denied
    /// Spotify is not installed or not running.
    case unavailable

    var isUsable: Bool { self == .ok || self == .undetermined }
}

protocol SpotifyControlling: AnyObject, Sendable {
    var isRunning: Bool { get }
    var access: SpotifyAccess { get }
    var playerState: SpotifyPlayerState { get }
    var soundVolume: Int { get set }

    func currentTrack() -> TrackInfo?
}

/// Holds no state, so it is safe to share across queues without a lock.
///
/// The `SBApplication` is built per call rather than cached. Caching it would
/// mean shared mutable state, which Swift cannot check for thread safety, and
/// the only way to keep it would be an unchecked promise. Building one costs
/// about 5.6 ms against roughly 33 ms for a single property read, and this app
/// reads only when Spotify signals a change.
final class SpotifyBridge: SpotifyControlling {

    static let bundleID = "com.spotify.client"

    /// Timeout for one event, in ticks of 1/60 s. A normal reply takes about
    /// 33 ms. Two seconds is a limit for when Spotify stops responding.
    private static let eventTimeoutTicks = 120

    var isRunning: Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.bundleID)
            .isEmpty
    }

    /// A denied app looks the same as an idle one without this check:
    /// `playerState` returns 0, which maps to `.stopped`, and `currentTrack`
    /// returns nil.
    var access: SpotifyAccess {
        guard isRunning else { return .unavailable }

        // Names Spotify by its bundle id, the way Apple events address an app.
        var target = AEAddressDesc()
        let bundleBytes = Array(Self.bundleID.utf8)
        guard AECreateDesc(typeApplicationBundleID, bundleBytes, bundleBytes.count, &target) == noErr
        else { return .unavailable }
        defer { AEDisposeDesc(&target) }

        // Asks the system whether we may control Spotify. Sends nothing.
        // false means report that consent is needed instead of prompting now.
        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false) {
        case noErr: return .ok
        case OSStatus(errAEEventWouldRequireUserConsent): return .undetermined
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unavailable
        }
    }

    /// Nil while Spotify is not running. Any message sent to an SBApplication
    /// launches the target app, so the guard keeps this app from starting
    /// Spotify.
    private func makeApp() -> SpotifyScriptingApplication? {
        guard isRunning else { return nil }
        guard let app = SBApplication(bundleIdentifier: Self.bundleID) else { return nil }
        app.timeout = Self.eventTimeoutTicks
        return app
    }

    var playerState: SpotifyPlayerState {
        guard let code = makeApp()?.playerState else { return .stopped }
        return SpotifyPlayerState(code: code)
    }

    var soundVolume: Int {
        get { makeApp()?.soundVolume ?? 0 }
        set { makeApp()?.setSoundVolume?(max(0, min(100, newValue))) }
    }

    func currentTrack() -> TrackInfo? {
        // One app object for all five reads below.
        guard let track = makeApp()?.currentTrack else { return nil }
        // Spotify returns a live object even when nothing is loaded. A missing
        // or empty id is how that appears.
        guard let id = track.id, !id.isEmpty else { return nil }

        return TrackInfo(
            id: id,
            name: track.name ?? "",
            artist: track.artist ?? "",
            album: track.album ?? "",
            durationMS: track.duration ?? 0
        )
    }
}
