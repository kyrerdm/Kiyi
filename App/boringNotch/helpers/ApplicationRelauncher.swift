//
//  ApplicationRelauncher.swift
//  boringNotch
//
//  Created by Corentin132 on 03/10/2025.
//

import AppKit

@MainActor
enum ApplicationRelauncher {
    static func restart(showSettings: Bool = false, onLaunchRequested: @escaping () -> Void) {
        if showSettings { UserDefaults.standard.set(true, forKey: "kiyiReopenSettings") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.arguments = ["--kiyi-relaunch"] + (showSettings ? ["--settings"] : [])
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: onLaunchRequested)
    }
}
