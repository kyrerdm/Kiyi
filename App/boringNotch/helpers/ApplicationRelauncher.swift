//
//  ApplicationRelauncher.swift
//  boringNotch
//
//  Created by Corentin132 on 03/10/2025.
//

import AppKit

@MainActor
enum ApplicationRelauncher {
    static func restart(onLaunchRequested: @escaping () -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.arguments = ["--kiyi-relaunch"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        onLaunchRequested()
    }
}
