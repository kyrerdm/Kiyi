import Foundation

func checkPreferences() throws {
    let suite = "Ada.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let prefs = Preferences(defaults: defaults)
    precondition(prefs.value.expandedWidth < 410, "Default must be smaller than v0.1")
    prefs.value.expandedWidth = 312
    prefs.value.expandedHeight = 196
    prefs.value.theme = "light"
    prefs.value.accentMode = "custom"
    prefs.value.red = 0.9
    prefs.value.transparency = 0.8
    prefs.value.hoverEnabled = false
    prefs.value.showArtist = false
    prefs.value.lockArtworkSize = 164
    let loaded = Preferences(defaults: defaults)
    precondition(loaded.value == prefs.value, "Every setting must survive restart")
    let exported = try JSONEncoder().encode(prefs.value)
    let imported = try JSONDecoder().decode(Configuration.self, from: exported)
    precondition(imported == prefs.value, "Export/import must preserve all settings")
    var bad = Configuration()
    bad.expandedWidth = -100; bad.expandedHeight = 9999; bad.transparency = 12
    bad.theme = "invalid"; bad.accentMode = "invalid"; bad.lockOffset = 9999
    bad.validate()
    precondition(bad.expandedWidth == 280 && bad.expandedHeight == 340)
    precondition(bad.transparency == 0.95 && bad.lockOffset == 140)
    precondition(bad.theme == "system" && bad.accentMode == "system")
    let compatible = try JSONDecoder().decode(Configuration.self, from: Data("{}".utf8))
    precondition(compatible == Configuration(), "Older settings must gain new defaults without data loss")
    let lrc = Lyrics.parse("[00:01.50]first\n[00:03.00][00:04.20]again")
    precondition(lrc.count == 3 && lrc[0].time == 1.5 && lrc[2].time == 4.2)
    precondition(Configuration().hoverDelay == 0 && Configuration().collapseDelay == 0)
    prefs.reset()
    precondition(Preferences(defaults: defaults).value == Configuration(), "Reset must persist defaults")
    print("PASS: smaller defaults; full persistence; JSON round trip; imported ranges; reset")
}
