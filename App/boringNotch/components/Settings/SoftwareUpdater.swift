//
//  SoftwareUpdater.swift
//  boringNotch
//
//  Created by Richard Kunkli on 09/08/2024.
//

import SwiftUI
import Sparkle

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater
    
    init(updater: SPUUpdater) {
        self.updater = updater
        
        // Create our view model for our CheckForUpdatesView
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }
    
    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class KiyiUpdaterSettingsModel: ObservableObject {
    let updater: SPUUpdater
    @Published private(set) var checks: Bool
    @Published private(set) var downloads: Bool
    @Published private(set) var interval: TimeInterval
    @Published private(set) var lastCheck: Date?
    @Published private(set) var canCheck: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        checks = updater.automaticallyChecksForUpdates
        downloads = updater.automaticallyDownloadsUpdates
        interval = updater.updateCheckInterval
        lastCheck = updater.lastUpdateCheckDate
        canCheck = updater.canCheckForUpdates
        // Observe Sparkle too: its update dialogs can change these preferences.
        updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main).assign(to: &$checks)
        updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: RunLoop.main).assign(to: &$downloads)
        updater.publisher(for: \.updateCheckInterval).receive(on: RunLoop.main).assign(to: &$interval)
        updater.publisher(for: \.lastUpdateCheckDate).receive(on: RunLoop.main).assign(to: &$lastCheck)
        updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
    }
    func setChecks(_ value: Bool) { checks = value; updater.automaticallyChecksForUpdates = value }
    func setDownloads(_ value: Bool) { downloads = value; updater.automaticallyDownloadsUpdates = value }
    func setHours(_ value: Int) {
        interval = TimeInterval(min(168, max(1, value))) * 3600
        updater.updateCheckInterval = interval
    }
}

struct UpdaterSettingsView: View {
    @StateObject private var model: KiyiUpdaterSettingsModel
    init(updater: SPUUpdater) {
        _model = StateObject(wrappedValue: KiyiUpdaterSettingsModel(updater: updater))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Automatically check for updates", isOn: Binding(get: { model.checks }, set: model.setChecks))
            Toggle("Automatically download updates", isOn: Binding(get: { model.downloads }, set: model.setDownloads))
                .disabled(!model.checks)
            Stepper(value: Binding(get: { Int(model.interval / 3600) }, set: model.setHours), in: 1...168) {
                HStack {
                    Text("Kontrol aralığı")
                    Spacer()
                    Text("\(Int(model.interval / 3600)) h").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .disabled(!model.checks)
            Text("1–168 saat arasında seçebilirsin. Kontroller Kıyı açıkken yapılır.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("Son kontrol").foregroundStyle(.secondary)
                Spacer()
                if let date = model.lastCheck {
                    Text(date, format: .dateTime.day().month().hour().minute())
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("Henüz kontrol edilmedi").foregroundStyle(.secondary)
                }
            }
            Button("Check for Updates…", action: model.updater.checkForUpdates)
                .disabled(!model.canCheck)
            Text("Yeni sürüm imzası doğrulandıktan sonra indirilir ve uygun kapanışta kurulur. macOS gerektiğinde onay isteyebilir.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Keep the normal Cmd-Q behavior, while allowing Sparkle's verified installer to quit.
final class KiyiUpdateDelegate: NSObject, SPUUpdaterDelegate {
    static let shared = KiyiUpdateDelegate()
    var installing = false
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        installing = true
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installing = false
    }
}
