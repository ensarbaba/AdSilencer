//
//  NotchTuneApp.swift
//  NotchTune
//
//  Menu bar only (LSUIElement): no Dock icon and no windows.
//
//  This is a deliberate stub. It exists so the app target links and runs from
//  the very first commit, which keeps every later piece independently
//  buildable. The real menu and the Spotify wiring arrive in a later piece.
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
