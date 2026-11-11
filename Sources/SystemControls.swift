import AppKit
import SwiftUI
import CoreAudio

struct AudioOutput: Identifiable { let id: AudioDeviceID; let name: String }
struct AudioAccessory: Identifiable {
    let id: String; let name: String; let connected: Bool
    let left: String?; let right: String?; let battery: String?; let caseBattery: String?
}
final class SystemControls: ObservableObject {
    static let shared = SystemControls()
    @Published var volume = 0.0
    @Published var muted = false
    @Published var brightness = 0.0
    @Published var volumeSupported = false
    @Published var brightnessSupported = false
    @Published var outputs: [AudioOutput] = []
    @Published var output: AudioDeviceID = 0
    @Published var accessories: [AudioAccessory] = []
    @Published var notice: String?
    var hud: ((String, String, Double) -> Void)?
    private var timer: Timer?
    private var bluetoothTimer: Timer?
    private var scanning = false
    private var hasRead = false
    private var channels: [AudioObjectPropertyElement] = []
    private var observed: AudioDeviceID = 0
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private let brightnessHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private var getBrightness: GetBrightness?
    private var setBrightness: SetBrightness?
    init() {
        if let h = brightnessHandle, let get = dlsym(h, "DisplayServicesGetBrightness"), let set = dlsym(h, "DisplayServicesSetBrightness") {
            getBrightness = unsafeBitCast(get, to: GetBrightness.self); setBrightness = unsafeBitCast(set, to: SetBrightness.self)
        }
        refreshRoute()
        listen(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal, element: 0) { [weak self] in self?.refreshRoute(); self?.refreshBluetooth() }
        listen(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal, element: 0) { [weak self] in self?.refreshRoute() }
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.readBrightness() }; RunLoop.main.add(timer!, forMode: .common)
        refreshBluetooth()
        bluetoothTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refreshBluetooth() }; RunLoop.main.add(bluetoothTimer!, forMode: .common)
    }
    func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ element: AudioObjectPropertyElement = 0) -> AudioObjectPropertyAddress { AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element) }
    func listen(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement, action: @escaping () -> Void) {
        var a = address(selector, scope, element)
        let block: AudioObjectPropertyListenerBlock = { _, _ in action() }
        if AudioObjectAddPropertyListenerBlock(object, &a, .main, block) == noErr { listeners.append((object, a, block)) }
    }
    func refreshRoute() {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice); var device: AudioDeviceID = 0; var size = UInt32(MemoryLayout.size(ofValue: device))
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &device) == noErr else { return }
        if device != output {
            let old = output
            listeners.removeAll { object, addr, block in
                guard object == old && old != 0 else { return false }; var a = addr; AudioObjectRemovePropertyListenerBlock(object, &a, .main, block); return true
            }
            output = device
            listen(object: device, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, element: 0) { [weak self] in self?.readVolume() }
            for channel: AudioObjectPropertyElement in [0, 1, 2] {
                listen(object: device, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: channel) { [weak self] in self?.readVolume() }
            }
        }
        var listAddress = address(kAudioHardwarePropertyDevices); var bytes: UInt32 = 0
        if AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &bytes) == noErr {
            var devices = [AudioDeviceID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioDeviceID>.size)
            if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &bytes, &devices) == noErr {
                outputs = devices.compactMap { id in
                    var streams = self.address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput); var size: UInt32 = 0
                    guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &size) == noErr, size > 0 else { return nil }
                    var nameAddress = self.address(kAudioObjectPropertyName); var name: Unmanaged<CFString>?; size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                    guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &size, &name) == noErr else { return nil }
                    return AudioOutput(id: id, name: (name?.takeRetainedValue() as String?) ?? "Ses çıkışı")
                }
            }
        }
        readVolume()
    }
    func readVolume() {
        var values: [Double] = []; channels = []
        for channel: AudioObjectPropertyElement in [0, 1, 2] {
            var a = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, channel); var v: Float32 = 0; var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(output, &a, 0, nil, &size, &v) == noErr {
                values.append(Double(v)); channels.append(channel); if channel == 0 { break }
            }
        }
        var muteAddress = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput); var mute: UInt32 = 0; var muteSize: UInt32 = 4
        if AudioObjectGetPropertyData(output, &muteAddress, 0, nil, &muteSize, &mute) == noErr { muted = mute != 0 }
        volumeSupported = !values.isEmpty
        if !values.isEmpty {
            let next = values.reduce(0,+) / Double(values.count)
            if abs(next - volume) > 0.001 { volume = next; if hasRead { hud?("Ses", "speaker.wave.2.fill", next) } }
        }
        hasRead = true
    }
    func changeVolume(_ value: Double) {
        var success = false
        for channel in channels {
            var a = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, channel); var level = Float32(min(1, max(0, value)))
            if AudioObjectSetPropertyData(output, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr { success = true }
        }
        if !success { notice = "Bu çıkışın sesi yazılımla değiştirilemiyor." }; readVolume()
    }
    func toggleMute() {
        var a = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput); var mute: UInt32 = muted ? 0 : 1
        if AudioObjectSetPropertyData(output, &a, 0, nil, 4, &mute) == noErr { readVolume(); hud?(muted ? "Sessiz" : "Ses", muted ? "speaker.slash.fill" : "speaker.wave.2.fill", muted ? 0 : volume) }
    }
    func selectOutput(_ id: AudioDeviceID) {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice); var id = id
        if AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id) != noErr { notice = "Ses çıkışı değiştirilemedi." }
        refreshRoute()
    }
    var display: UInt32 { NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }).map { UInt32(screenID($0)) ?? CGMainDisplayID() } ?? CGMainDisplayID() }
    func readBrightness() {
        var value: Float = 0
        guard let get = getBrightness, get(display, &value) == 0 else { brightnessSupported = false; return }
        let initial = !brightnessSupported; brightnessSupported = true
        let next = Double(value)
        if abs(next - brightness) > 0.002 { brightness = next; if !initial { hud?("Parlaklık", "sun.max.fill", next) } }
    }
    func changeBrightness(_ value: Double) {
        if setBrightness?(display, Float(max(0.01, min(1, value)))) != 0 { notice = "Bu ekranın parlaklığı değiştirilemedi." }
        readBrightness()
    }
    func refreshBluetooth() {
        guard !scanning else { return }; scanning = true
        DispatchQueue.global(qos: .utility).async {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler"); process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            var found: [AudioAccessory] = []
            do {
                try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let reports = json["SPBluetoothDataType"] as? [[String: Any]] {
                    for report in reports {
                        for kind in ["device_connected", "device_not_connected"] {
                            for item in report[kind] as? [[String: [String: Any]]] ?? [] {
                                for (name, info) in item where name.localizedCaseInsensitiveContains("airpod") || ["Headphones", "Headset"].contains(info["device_minorType"] as? String ?? "") {
                                    found.append(AudioAccessory(id: info["device_address"] as? String ?? name, name: name, connected: kind == "device_connected", left: info["device_batteryLevelLeft"] as? String, right: info["device_batteryLevelRight"] as? String, battery: info["device_batteryLevelMain"] as? String, caseBattery: info["device_batteryLevelCase"] as? String))
                                }
                            }
                        }
                    }
                }
            } catch {}
            DispatchQueue.main.async {
                let old = Set(self.accessories.filter(\.connected).map(\.id))
                self.accessories = found; self.scanning = false
                if let connected = found.first(where: { $0.connected && !old.contains($0.id) }) { self.hud?(connected.name, "airpodspro", 1) }
            }
        }
    }
}
struct SystemControlsView: View {
    @ObservedObject var controls = SystemControls.shared
    @EnvironmentObject var prefs: Preferences
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Button { controls.toggleMute() } label: { Image(systemName: controls.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 18) }.buttonStyle(.plain).help("Sessiz / sesi aç"); Slider(value: Binding(get: { controls.volume }, set: controls.changeVolume), in: 0...1).disabled(!controls.volumeSupported).accessibilityLabel("Sistem sesi"); Text("\(Int(controls.volume * 100))%").font(.caption).monospacedDigit().frame(width: 34) }
                HStack { Image(systemName: "sun.max.fill").frame(width: 18); Slider(value: Binding(get: { controls.brightness }, set: controls.changeBrightness), in: 0.01...1).disabled(!controls.brightnessSupported).accessibilityLabel("Ekran parlaklığı"); Text("\(Int(controls.brightness * 100))%").font(.caption).monospacedDigit().frame(width: 34) }
                Picker("Ses çıkışı", selection: Binding(get: { controls.output }, set: controls.selectOutput)) { ForEach(controls.outputs) { Text($0.name).tag($0.id) } }.font(.caption)
                if prefs.value.airpodsEnabled {
                    ForEach(controls.accessories) { device in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: device.name.localizedCaseInsensitiveContains("airpod") ? "airpodspro" : "headphones")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name).font(.system(size: 11, weight: .medium))
                                Text(device.connected ? "Bağlı" : "Bağlı değil").font(.system(size: 9)).foregroundStyle(.secondary)
                                if device.connected {
                                    HStack { if let left = device.left { Text("Sol \(left)") }; if let right = device.right { Text("Sağ \(right)") }; if let battery = device.battery { Text(battery) }; if let box = device.caseBattery { Text("Kutu \(box)") } }.font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 3)
                    }
                    if controls.accessories.isEmpty { Text("Bağlı kulaklık bilgisi yok.").font(.caption).foregroundStyle(.secondary) }
                }
                if let notice = controls.notice { Text(notice).font(.caption).foregroundStyle(.orange) }
            }.padding(10).tint(prefs.accent)
        }
    }
}

extension SystemControls {
    private static var eventTap: CFMachPort?
    private static var eventSource: CFRunLoopSource?
    func configureInterceptor(_ enabled: Bool) {
        guard enabled else {
            if let tap = Self.eventTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
            if let source = Self.eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            Self.eventTap = nil; Self.eventSource = nil; return
        }
        guard Self.eventTap == nil else { return }
        guard AXIsProcessTrusted() else { notice = "Sistem HUD değişimi için Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik’te Ada’ya izin ver."; return }
        let mask = CGEventMask(1 << 14)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap = SystemControls.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }; return Unmanaged.passUnretained(event) }
            guard let key = NSEvent(cgEvent: event), key.type == .systemDefined, key.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
            let code = (key.data1 >> 16) & 0xffff
            guard [0, 1, 7, 16, 17].contains(code) else { return Unmanaged.passUnretained(event) }
            if code <= 7 && !SystemControls.shared.volumeSupported { return Unmanaged.passUnretained(event) }
            if code >= 16 && !SystemControls.shared.brightnessSupported { return Unmanaged.passUnretained(event) }
            if ((key.data1 >> 8) & 0xff) == 0x0a {
                DispatchQueue.main.async {
                    let c = SystemControls.shared
                    switch code {
                    case 0: c.changeVolume(c.volume + 1.0 / 16)
                    case 1: c.changeVolume(c.volume - 1.0 / 16)
                    case 7: c.toggleMute()
                    case 16: c.changeBrightness(c.brightness + 1.0 / 16)
                    case 17: c.changeBrightness(c.brightness - 1.0 / 16)
                    default: break
                    }
                }
            }
            return nil
        }, userInfo: nil) else { notice = "Medya tuşlarına erişim kurulamadı."; return }
        Self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        Self.eventSource = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: tap, enable: true)
    }
}
