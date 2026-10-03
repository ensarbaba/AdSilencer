//
//  SetupStep.swift
//  AdSilencer
//
//  One row of the onboarding checklist. The title says whether the step is
//  done, so the status image is decorative.
//

import SwiftUI

struct SetupStep<Action: View>: View {

    let isDone: Bool
    let doneTitle: LocalizedStringKey
    let todoTitle: LocalizedStringKey
    @ViewBuilder let action: Action

    var body: some View {
        Label {
            if isDone {
                Text(doneTitle)
            } else {
                VStack(alignment: .leading) {
                    Text(todoTitle)
                    action
                }
            }
        } icon: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Color.green : Color.secondary)
                .accessibilityHidden(true)
        }
    }
}
