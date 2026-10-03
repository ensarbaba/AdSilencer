//
//  AdSilencerApp.swift
//  AdSilencer
//
//  Menu bar app. LSUIElement, so no Dock icon. The only window is the
//  onboarding checklist.
//

import SwiftUI

@main
struct AdSilencerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: delegate.state)
        } label: {
            MenuBarLabel(state: delegate.state)
        }
        .menuBarExtraStyle(.menu)

        Window("Welcome to AdSilencer", id: OnboardingView.windowID) {
            OnboardingView(state: delegate.state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowLevel(delegate.onboardingWindowLevel)
        .defaultLaunchBehavior(delegate.onboardingLaunchBehavior)
    }
}
