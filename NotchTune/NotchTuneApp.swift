//
//  NotchTuneApp.swift
//  NotchTune
//
//  Menu bar app. LSUIElement, so no Dock icon and no windows.
//  Placeholder menu until the Spotify wiring lands.
//

import AppKit
import SwiftUI

@main
struct NotchTuneApp: App {
    var body: some Scene {
        MenuBarExtra("NotchTune", systemImage: "music.note") {
            Text("NotchTune")

            Divider()

            Button("Quit NotchTune") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
