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

// Privacy status is read only until the user explicitly presses an action.
import AVFoundation
import EventKit
import ApplicationServices
import Carbon

private enum KiyiPermission: String, CaseIterable, Identifiable {
    case controls, camera, calendar, reminders, spotify, music
    var id: Self { self }
    var title: String {
        switch self {
        case .controls: "Aygıt denetimi ve erişilebilirlik"
        case .camera: "Kamera"
        case .calendar: "Takvim"
        case .reminders: "Hatırlatıcılar"
        case .spotify: "Spotify otomasyonu"
        case .music: "Apple Music otomasyonu"
        }
    }
    var detail: String {
        switch self {
        case .controls: "Ses/parlaklık tuşları, Gelgit ve Spotify beğeni kontrolü için gerekir. Ana uygulama ve yardımcı ayrı kontrol edilir."
        case .camera: "Yalnızca kamera aynasını kullanmak istersen gerekir."
        case .calendar: "Takvim etkinliklerini göstermek için tam okuma erişimi gerekir."
        case .reminders: "Hatırlatıcılarını göstermek istersen gerekir."
        case .spotify, .music: "Parça bilgisini okumak ve oynatmayı denetlemek için gerekir. Durum uygulamaya özeldir."
        }
    }
    var pane: String {
        switch self {
        case .controls: "Privacy_Accessibility"
        case .camera: "Privacy_Camera"
        case .calendar: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .spotify, .music: "Privacy_Automation"
        }
    }
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}

private enum KiyiPermissionState: String {
    case granted = "İzin verilmiş", needed = "İzin gerekli", denied = "İzin reddedilmiş"
    case restricted = "Sistem tarafından kısıtlanmış", unknown = "Doğrulanamadı"
    case closed = "Uygulama kapalı", missing = "Uygulama yüklü değil"
    case partial = "Kısmi erişim"
}

@MainActor private final class KiyiPermissionsModel: ObservableObject {
    @Published var states: [KiyiPermission: KiyiPermissionState] = [:]
    @Published var busy = false
    @Published var mainControl = false
    @Published var helperControl = false
    private let store = EKEventStore()
    private var refreshing = false

    func refresh() async {
        guard !refreshing, !busy else { return }
        refreshing = true
        defer { refreshing = false }
        mainControl = AXIsProcessTrusted()
        helperControl = await XPCHelperClient.shared.isAccessibilityAuthorized()
        states[.controls] = mainControl && helperControl ? .granted : (mainControl || helperControl ? .partial : .needed)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: states[.camera] = .granted
        case .notDetermined: states[.camera] = .needed
        case .denied: states[.camera] = .denied
        case .restricted: states[.camera] = .restricted
        @unknown default: states[.camera] = .unknown
        }
        for (permission, entity) in [(KiyiPermission.calendar, EKEntityType.event), (.reminders, .reminder)] {
            switch EKEventStore.authorizationStatus(for: entity) {
            case .fullAccess: states[permission] = .granted
            case .notDetermined: states[permission] = .needed
            case .denied: states[permission] = .denied
            case .restricted: states[permission] = .restricted
            case .writeOnly: states[permission] = .partial
            default: states[permission] = .unknown
            }
        }
        for permission in [KiyiPermission.spotify, .music] {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: permission.bundleID) != nil else {
                states[permission] = .missing; continue
            }
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: permission.bundleID).isEmpty else {
                states[permission] = .closed; continue
            }
            let id = permission.bundleID
            let code = await Task.detached { Self.automation(id, prompt: false) }.value
            states[permission] = Self.automationState(code)
        }
    }
    nonisolated private static func automation(_ id: String, prompt: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: id)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, prompt)
    }
    nonisolated private static func automationState(_ code: OSStatus) -> KiyiPermissionState {
        switch code {
        case noErr: .granted
        case -1744: .needed
        case -1743: .denied
        case -600: .closed
        default: .unknown
        }
    }
    func openSettings(_ permission: KiyiPermission) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + permission.pane) {
            NSWorkspace.shared.open(url)
        }
    }
    func request(_ permission: KiyiPermission) async {
        guard !busy else { return }
        busy = true
        switch permission {
        case .controls:
            if !mainControl { MediaKeyInterceptor.shared.requestAccessibilityAuthorization() }
            if !helperControl { XPCHelperClient.shared.requestAccessibilityAuthorization() }
            openSettings(permission)
        case .camera:
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            } else { openSettings(permission) }
        case .calendar:
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined || EKEventStore.authorizationStatus(for: .event) == .writeOnly {
                _ = try? await store.requestFullAccessToEvents()
            } else { openSettings(permission) }
        case .reminders:
            if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
                _ = try? await store.requestFullAccessToReminders()
            } else { openSettings(permission) }
        case .spotify, .music:
            if states[permission] == .closed {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: permission.bundleID) { NSWorkspace.shared.open(url) }
            } else if states[permission] == .denied || states[permission] == .granted {
                openSettings(permission)
            } else {
                let id = permission.bundleID
                _ = await Task.detached { Self.automation(id, prompt: true) }.value
            }
        }
        busy = false
        await refresh()
    }
}

struct KiyiPermissionsView: View {
    @StateObject private var model = KiyiPermissionsModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Yalnızca kullanacağın özelliklere izin ver. Durumlar bu kurulu sürüm için kontrol edilir; izin onaylarını macOS üzerinden sen verirsin.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(KiyiPermission.allCases) { permission in
                let state = model.states[permission] ?? .unknown
                VStack(alignment: .leading, spacing: 10) {
                    Text(KiyiL(permission.title)).font(.headline)
                    Text(KiyiL(permission.detail)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Label(KiyiL(state.rawValue), systemImage: state == .granted ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(state == .granted ? Color.green : Color.secondary)
                    if permission == .controls {
                        Text(KiyiL("Ana uygulama") + ": " + KiyiL(model.mainControl ? "İzin verilmiş" : "İzin gerekli") + " · " + KiyiL("Yardımcı") + ": " + KiyiL(model.helperControl ? "İzin verilmiş" : "Doğrulanamadı"))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(KiyiL(state == .closed ? "Uygulamayı aç" : state == .granted || state == .denied || state == .restricted ? "Sistem Ayarları’nı aç" : "İzin iste")) {
                        Task { await model.request(permission) }
                    }.disabled(model.busy || state == .missing || state == .restricted)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Ad-hoc imzalı bir güncellemeden sonra macOS izni tekrar isteyebilir. Yardımcı durumu doğrulanamıyorsa Kıyı’yı menüden kapatıp yeniden açmayı dene.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }
}
