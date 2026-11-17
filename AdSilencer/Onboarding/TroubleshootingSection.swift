//
//  TroubleshootingSection.swift
//  AdSilencer
//
//  Repair controls for the setup window.
//

import Foundation
import SwiftUI

enum RepairOutcome: Equatable {
    case done
    case cancelled
    case failed(String)

    init(error: NSDictionary?) {
        guard let error else {
            self = .done
            return
        }

        let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        if number == -128 {
            self = .cancelled
        } else if let message = error[NSAppleScript.errorMessage] as? String {
            self = .failed(message)
        } else if let number {
            self = .failed("macOS reports error \(number).")
        } else {
            self = .failed("macOS could not restart Apple Events.")
        }
    }

    var message: String {
        switch self {
        case .done: "macOS restarted Apple Events."
        case .cancelled: "You cancelled the restart."
        case .failed(let message): message
        }
    }
}

struct TroubleshootingSection: View {
    @Bindable var state: AppState
    @Binding var isExpanded: Bool
    @State private var result: String?

    var body: some View {
        DisclosureGroup("Troubleshooting", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Restart Apple Events") {
                    result = state.restartAppleEvents().message
                }

                if let result {
                    Text(result)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        }
    }
}
