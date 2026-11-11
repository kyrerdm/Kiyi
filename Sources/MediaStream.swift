import AppKit

// MediaRemoteAdapter integration, following TheBoredTeam/boring.notch's NowPlayingController.
// The helper and its original license are bundled unchanged; see THIRD_PARTY_NOTICES.md.
extension Spotify {
    func setSourceMode(_ mode: String) {
        guard sourceMode != mode else { return }
        sourceMode = mode
        remoteProcess?.terminationHandler = nil
        if remoteProcess?.isRunning == true { remoteProcess?.terminate() }
        remoteProcess = nil; streamHealthy = false; remoteBuffer = Data()
        guard mode == "system" else { refresh(); return }
        startStream()
    }
    func startStream() {
        guard sourceMode == "system", remoteProcess?.isRunning != true,
              let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = Bundle.main.privateFrameworksPath else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, framework + "/MediaRemoteAdapter.framework", "stream", "--no-diff"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.sourceMode == "system", self.remoteProcess === p else { return }
                self.remoteBuffer.append(data)
                while let end = self.remoteBuffer.firstIndex(of: 10) {
                    let line = self.remoteBuffer.prefix(upTo: end); self.remoteBuffer.removeSubrange(...end)
                    if let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] { self.acceptRemote(json) }
                }
            }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.remoteProcess === p else { return }
                self.streamHealthy = false; self.remoteProcess = nil
                self.message = "Sistem medya bağlantısı yenileniyor; Spotify yedeği etkin."
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.startStream() }
            }
        }
        do { try p.run(); remoteProcess = p }
        catch { message = "Sistem medya yardımcısı başlatılamadı; Spotify kullanılacak." }
    }
    func acceptRemote(_ json: [String: Any]) {
        let payload = json["payload"] as? [String: Any] ?? json
        guard let t = payload["title"] as? String, !t.isEmpty else { return }
        streamHealthy = true; message = nil
        title = t; artist = payload["artist"] as? String ?? ""
        sourceIdentifier = payload["parentApplicationBundleIdentifier"] as? String ?? payload["bundleIdentifier"] as? String ?? ""
        playing = payload["playing"] as? Bool ?? false
        duration = payload["duration"] as? Double ?? 0
        position = payload["elapsedTime"] as? Double ?? 0; stamp = Date()
        if let timestamp = payload["timestamp"] as? String, let date = ISO8601DateFormatter().date(from: timestamp), playing { position += max(0, Date().timeIntervalSince(date)) }
        if let image = payload["artworkData"] as? String, let data = Data(base64Encoded: image, options: .ignoreUnknownCharacters), let cover = NSImage(data: data) { artwork = cover }
        else { artwork = nil }
    }
    func remoteCommand(_ args: [String]) {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"), let frameworks = Bundle.main.privateFrameworksPath else { return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/perl"); p.arguments = [script.path, frameworks + "/MediaRemoteAdapter.framework"] + args
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do { try p.run(); p.waitUntilExit() } catch {}
        }
    }
}
