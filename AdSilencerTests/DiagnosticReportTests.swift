//
//  DiagnosticReportTests.swift
//  AdSilencerTests
//

import Testing
@testable import AdSilencer

struct DiagnosticReportTests {

    @Test("The report describes working Spotify")
    func workingSpotify() {
        let playback = Playback(
            isSpotifyRunning: true,
            access: .ok,
            state: .playing,
            trackID: .song()
        )

        let report = DiagnosticReport.make(
            appVersion: "2026.11.15 (1)",
            macOSVersion: "27.0.0",
            spotifyVersion: "1.3.6.1921",
            playback: playback,
            noAnswerDuration: nil,
            isMuteEnabled: true
        )

        #expect(report.contains("Spotify: 1.3.6.1921"))
        #expect(report.contains("Access: allowed"))
        #expect(report.contains("Time without an answer: none"))
        #expect(report.contains("Mute ads: on"))
    }

    @Test("The report gives the time without an answer")
    func noAnswer() {
        let report = DiagnosticReport.make(
            appVersion: "local build",
            macOSVersion: "27.0.0",
            spotifyVersion: "1.3.6.1921",
            playback: .waiting(.noAnswer),
            noAnswerDuration: 12.8,
            isMuteEnabled: false
        )

        #expect(report.contains("Access: no answer"))
        #expect(report.contains("Time without an answer: 12 s"))
        #expect(report.contains("Mute ads: off"))
    }

    @Test("The report describes missing Spotify")
    func noSpotify() {
        let report = DiagnosticReport.make(
            appVersion: "local build",
            macOSVersion: "27.0.0",
            spotifyVersion: nil,
            playback: .idle,
            noAnswerDuration: nil,
            isMuteEnabled: true
        )

        #expect(report.contains("Spotify: not installed"))
        #expect(report.contains("Spotify running: no"))
        #expect(report.contains("Access: unavailable"))
    }
}
