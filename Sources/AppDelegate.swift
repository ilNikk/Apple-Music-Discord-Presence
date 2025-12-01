import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var contentView: PopoverContentView!
    var discord: DiscordRPC!
    var updateTimer: Timer?
    var reconnectTimer: Timer?
    var lastTrack: String = ""
    var isEnabled = true
    var isReconnecting = false
    var currentArtworkURL: String?
    let discordClientId = "1445087052608835676"
    let appBundleIdentifier = "com.ilnikk.MusicDiscordPresence"
    let currentVersion = "0.0.3"
    let githubRepo = "ilNikk/Apple-Music-Discord-Presence"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Music Discord Presence")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        contentView = PopoverContentView(frame: NSRect(x: 0, y: 0, width: 280, height: 280))
        contentView.delegate = self
        contentView.updateLoginToggle(isStartAtLoginEnabled())
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 280)
        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = contentView
        
        discord = DiscordRPC(clientId: discordClientId)
        connectToDiscord()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updatePresence()
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }
    
    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    func connectToDiscord() {
        guard !isReconnecting else { return }
        isReconnecting = true
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            let connected = self?.discord.connect() ?? false
            DispatchQueue.main.async {
                self?.isReconnecting = false
                if connected {
                    self?.reconnectTimer?.invalidate()
                    self?.reconnectTimer = nil
                    self?.contentView.updateStatus("✅ Connected to Discord")
                    self?.updatePresence()
                } else {
                    self?.contentView.updateStatus("❌ Discord not connected")
                    self?.scheduleReconnect()
                }
            }
        }
    }
    
    func scheduleReconnect() {
        guard reconnectTimer == nil else { return }
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.contentView.updateStatus("🔄 Reconnecting...")
            self?.discord.disconnect()
            self?.isReconnecting = false
            self?.connectToDiscord()
        }
    }
    
    func handleConnectionLost() {
        discord.disconnect()
        lastTrack = ""
        contentView.updateStatus("⚠️ Connection lost - Reconnecting...")
        scheduleReconnect()
    }
    
    @objc func reconnectDiscord() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        contentView.updateStatus("🔄 Reconnecting...")
        discord.disconnect()
        lastTrack = ""
        isReconnecting = false
        connectToDiscord()
    }
    
    @objc func togglePresence() {
        isEnabled.toggle()
        contentView.enableToggle.state = isEnabled ? .on : .off
        
        if !isEnabled {
            _ = discord.clearActivity()
            contentView.updateStatus("⏸ Presence disabled")
            contentView.updateTrackInfo(track: nil, artist: nil, album: nil, artwork: nil)
        } else {
            updatePresence()
        }
    }
    
    func isStartAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }
    
    @objc func toggleStartAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
                contentView.updateLoginToggle(SMAppService.mainApp.status == .enabled)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Cannot change login item"
                alert.informativeText = "Please add the app manually in System Settings > General > Login Items"
                alert.alertStyle = .warning
                alert.runModal()
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "Not supported"
            alert.informativeText = "Start at Login requires macOS 13 or later"
            alert.alertStyle = .informational
            alert.runModal()
        }
    }
    
    @objc func checkForUpdates() {
        let urlString = "https://api.github.com/repos/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.showUpdateAlert(title: "Update Check Failed", message: "Could not connect to GitHub: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self.showUpdateAlert(title: "Update Check Failed", message: "Could not parse response from GitHub")
                    return
                }
                
                let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                
                if self.compareVersions(latestVersion, self.currentVersion) > 0 {
                    let alert = NSAlert()
                    alert.messageText = "Update Available"
                    alert.informativeText = "A new version (\(tagName)) is available. You are running v\(self.currentVersion)."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Download")
                    alert.addButton(withTitle: "Later")
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let downloadURL = URL(string: "https://github.com/\(self.githubRepo)/releases/latest") {
                            NSWorkspace.shared.open(downloadURL)
                        }
                    }
                } else {
                    self.showUpdateAlert(title: "You're Up to Date", message: "You are running the latest version (v\(self.currentVersion)).")
                }
            }
        }.resume()
    }
    
    func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return 1 }
            if p1 < p2 { return -1 }
        }
        return 0
    }
    
    func showUpdateAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    func updatePresence() {
        guard isEnabled else { return }
        
        if let track = MusicHelper.getCurrentTrack() {
            let trackId = "\(track.name)-\(track.artist)"
            
            if trackId != lastTrack {
                lastTrack = trackId
                
                let details = track.name
                let state = "by \(track.artist)"
                
                let localArtwork = MusicHelper.getLocalArtwork()
                DispatchQueue.main.async { [weak self] in
                    self?.contentView.updateTrackInfo(track: track.name, artist: track.artist, album: track.album, artwork: localArtwork)
                }
                
                MusicHelper.getArtworkURL(track: track.name, artist: track.artist, album: track.album, storeID: track.storeID) { [weak self] artworkURL in
                    self?.currentArtworkURL = artworkURL
                    
                    DispatchQueue.global(qos: .background).async {
                        let success = self?.discord.setActivity(
                            details: details,
                            state: state,
                            trackName: track.name,
                            largeImage: artworkURL,
                            largeText: track.album
                        ) ?? false
                        
                        DispatchQueue.main.async {
                            if !success && self?.discord.isConnected == false {
                                self?.handleConnectionLost()
                            } else if success {
                                self?.contentView.updateStatus("✅ Connected")
                            }
                        }
                    }
                }
            }
        } else {
            if !lastTrack.isEmpty {
                lastTrack = ""
                _ = discord.clearActivity()
                contentView.updateStatus("⏹ No track playing")
                contentView.updateTrackInfo(track: nil, artist: nil, album: nil, artwork: nil)
            }
        }
    }
    
    @objc func quit() {
        _ = discord.clearActivity()
        discord.disconnect()
        NSApplication.shared.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
        reconnectTimer?.invalidate()
        _ = discord.clearActivity()
        discord.disconnect()
    }
}
