//
//  SpotifyAdStateFile.swift
//  NotchTune
//
//  Watches ad-state-storage.bnk, which Spotify rewrites on ad changes. The
//  playback notification misses ad boundaries; this file does not.
//
//  Spotify replaces the file instead of writing into it, so deletes and
//  renames count as changes and the watch reopens the new file.
//
//  The account folder name varies per login, so it is searched for.
//

import Foundation
import Synchronization

/// `Mutex` guards the state, so Swift checks the `Sendable` conformance.
final class SpotifyAdStateFile: Sendable {

    private struct State {
        var source: DispatchSourceFileSystemObject?
        var watchedURL: URL?
        /// False after `stop()`, so a pending reopen gives up.
        var isRunning = false
    }

    /// Events meaning the file was replaced rather than edited.
    ///
    /// Computed rather than stored: `FileSystemEvent` is not `Sendable`, so a
    /// stored global would need an unsafe opt-out.
    private static var replacedEvents: DispatchSource.FileSystemEvent {
        [.delete, .rename, .revoke]
    }

    /// How long to wait before looking for the replacement file.
    private static let reopenDelay: TimeInterval = 0.1
    private static let reopenAttempts = 10

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
            // written to, grown, deleted, renamed, or the volume went away
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )
        // weak source: the source owns this handler, so a strong capture would
        // keep them both alive forever.
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let events = source.data
            self.onChange()

            // The file this descriptor points at is gone. Open the new one.
            if !events.isDisjoint(with: Self.replacedEvents) {
                self.reopen(url)
            }
        }
        // Closes the file when the watch ends.
        source.setCancelHandler { close(descriptor) }

        state.withLock {
            $0.source = source
            $0.watchedURL = url
            $0.isRunning = true
        }
        source.resume()
        return true
    }

    func stop() {
        // Takes the source out and clears it together, then cancels outside
        // the lock so the cancel handler cannot block on it.
        let source = state.withLock { state -> DispatchSourceFileSystemObject? in
            defer {
                state.source = nil
                state.isRunning = false
            }
            return state.source
        }
        source?.cancel()
    }

    /// Reopens the replacement file. It may not exist for a moment after the
    /// old one is removed, so this retries briefly before giving up.
    private func reopen(_ url: URL, attempt: Int = 0) {
        guard state.withLock({ $0.isRunning }) else { return }
        guard attempt < Self.reopenAttempts else { return }
        if start(watching: url) { return }

        queue.asyncAfter(deadline: .now() + Self.reopenDelay) { [weak self] in
            self?.reopen(url, attempt: attempt + 1)
        }
    }
}
