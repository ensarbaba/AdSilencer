//
//  SpotifyAdStateFileTests.swift
//  NotchTuneTests
//

import Foundation
import Synchronization
import Testing
@testable import NotchTune

/// Counts callbacks from the watcher's queue.
private final class Counter: Sendable {
    private let value = Mutex(0)

    func increment() { value.withLock { $0 += 1 } }
    var count: Int { value.withLock { $0 } }

    /// Waits up to `timeout` for the count to reach `target`.
    func wait(for target: Int, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if count >= target { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return count >= target
    }
}

struct SpotifyAdStateFileTests {

    private func makeScratchFile() throws -> (dir: URL, file: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchtune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("ad-state-storage.bnk")
        try Data("initial".utf8).write(to: file)
        return (dir, file)
    }

    @Test("A write to the file reports a change")
    func firesOnWrite() async throws {
        let (dir, file) = try makeScratchFile()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = Counter()
        let watcher = SpotifyAdStateFile(queue: DispatchQueue(label: "test.write")) {
            counter.increment()
        }
        #expect(watcher.start(watching: file))
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(100))
        try Data("changed".utf8).write(to: file)

        #expect(await counter.wait(for: 1))
    }

    @Test("The watch survives the file being replaced")
    func survivesAtomicReplace() async throws {
        // Spotify replaces this file rather than writing into it, which swaps
        // the inode. A watch that only handled writes would go deaf here.
        let (dir, file) = try makeScratchFile()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = Counter()
        let watcher = SpotifyAdStateFile(queue: DispatchQueue(label: "test.replace")) {
            counter.increment()
        }
        #expect(watcher.start(watching: file))
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(100))
        try Data("first".utf8).write(to: file, options: .atomic)
        #expect(await counter.wait(for: 1))

        // Give the reopen time to attach to the replacement.
        try await Task.sleep(for: .milliseconds(400))
        let before = counter.count

        try Data("second".utf8).write(to: file, options: .atomic)
        #expect(await counter.wait(for: before + 1))
    }

    @Test("Stopping ends the reports")
    func stopEndsNotifications() async throws {
        let (dir, file) = try makeScratchFile()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = Counter()
        let watcher = SpotifyAdStateFile(queue: DispatchQueue(label: "test.stop")) {
            counter.increment()
        }
        #expect(watcher.start(watching: file))

        watcher.stop()
        try await Task.sleep(for: .milliseconds(100))
        try Data("ignored".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(300))

        #expect(counter.count == 0)
    }

    @Test("A missing file is reported, not crashed on")
    func missingFileReturnsFalse() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).bnk")
        let watcher = SpotifyAdStateFile(queue: DispatchQueue(label: "test.missing")) {}
        #expect(watcher.start(watching: missing) == false)
    }

    @Test("The real Spotify file is found on this Mac")
    func locatesRealFile() {
        // A Mac that never signed in to Spotify has no such file, and the app
        // falls back to the playback notification alone.
        if let url = SpotifyAdStateFile.locate() {
            #expect(url.lastPathComponent == "ad-state-storage.bnk")
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }
}
