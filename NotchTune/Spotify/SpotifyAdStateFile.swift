//
//  SpotifyAdStateFile.swift
//  NotchTune
//
//  Watches the file Spotify rewrites when its ad state changes:
//
//      ~/Library/Application Support/Spotify/Users/<account>-user/ad-state-storage.bnk
//
//  Spotify's playback notification covers play, pause and seek, and is
//  coalesced, so it does not fire at every ad boundary. This file does.
//
//  The account folder name changes per login, so it is searched for.
//

import Foundation
import Synchronization

/// `Mutex` guards the state, so Swift checks the `Sendable` conformance.
final class SpotifyAdStateFile: Sendable {

    private struct State {
        var source: DispatchSourceFileSystemObject?
    }

    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private let state = Mutex(State())

    init(queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        self.queue = queue
        self.onChange = onChange
    }

    deinit {
        state.withLock { $0.source?.cancel() }
    }

    /// The ad state file for the account that used Spotify most recently, or
    /// nil when Spotify has never signed in on this Mac.
    static func locate() -> URL? {
        let root = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Spotify/Users", isDirectory: true)

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let candidates = entries
            .map { $0.appendingPathComponent("ad-state-storage.bnk") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        // Several accounts may have signed in over time. Newest file wins.
        return candidates.max { lhs, rhs in
            modified(lhs) < modified(rhs)
        }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    /// Returns false when the file cannot be found or opened.
    @discardableResult
    func start() -> Bool {
        guard let url = Self.locate() else { return false }
        return start(watching: url)
    }

    /// Explicit path, so tests can watch a scratch file instead of Spotify's.
    @discardableResult
    func start(watching url: URL) -> Bool {
        stop()

        // Opens the file only to get events. Does not keep the disk busy.
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        // Asks the kernel to report changes to this file.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend], // file written to, or grown
            queue: queue
        )
        source.setEventHandler { [onChange] in onChange() }
        // Closes the file when the watch ends.
        source.setCancelHandler { close(descriptor) }

        state.withLock { $0.source = source }
        source.resume()
        return true
    }

    func stop() {
        // Takes the source out and clears it together, then cancels outside
        // the lock so the cancel handler cannot block on it.
        let source = state.withLock { state -> DispatchSourceFileSystemObject? in
            defer { state.source = nil }
            return state.source
        }
        source?.cancel()
    }
}
