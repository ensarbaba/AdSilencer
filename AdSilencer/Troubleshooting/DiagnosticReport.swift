//
//  DiagnosticReport.swift
//  AdSilencer
//
//  Text for a troubleshooting report.
//

import Foundation

enum DiagnosticReport {
    static func make(
        appVersion: String,
        macOSVersion: String,
        spotifyVersion: String?,
        playback: Playback,
        noAnswerDuration: TimeInterval?,
        isMuteEnabled: Bool
    ) -> String {
        let noAnswer = noAnswerDuration.map { "\(Int($0.rounded(.down))) s" } ?? "none"
        return """
            AdSilencer diagnostic report
            AdSilencer: \(appVersion)
            macOS: \(macOSVersion)
            Spotify: \(spotifyVersion ?? "not installed")
            Spotify running: \(playback.isSpotifyRunning ? "yes" : "no")
            Access: \(playback.access.reportDescription)
            Time without an answer: \(noAnswer)
            Mute ads: \(isMuteEnabled ? "on" : "off")
            """
    }
}

private extension SpotifyAccess {
    var reportDescription: String {
        switch self {
        case .ok: "allowed"
        case .undetermined: "undetermined"
        case .denied: "denied"
        case .unavailable: "unavailable"
        case .noAnswer: "no answer"
        case .failed(let status): "error \(status)"
        }
    }
}
