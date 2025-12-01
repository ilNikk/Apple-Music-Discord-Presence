import Cocoa
import ServiceManagement

signal(SIGPIPE, SIG_IGN)

class DiscordRPC {
    private var socket: Int32 = -1
    private let clientId: String
    private(set) var isConnected = false
    private var isReady = false
    
    private enum Opcode: UInt32 {
        case handshake = 0
        case frame = 1
        case close = 2
        case ping = 3
        case pong = 4
    }
    
    init(clientId: String) {
        self.clientId = clientId
    }
    
    func connect() -> Bool {
        let tempPaths = [
            ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"],
            ProcessInfo.processInfo.environment["TMPDIR"],
            NSTemporaryDirectory(),
            "/tmp"
        ].compactMap { $0 }
        
        for tempPath in tempPaths {
            for i in 0..<10 {
                let socketPath = "\(tempPath)/discord-ipc-\(i)"
                
                socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                if socket == -1 { continue }
                
                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                
                let pathBytes = socketPath.utf8CString
                withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                    let bound = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { $0 }
                    for (index, byte) in pathBytes.enumerated() where index < 104 {
                        bound[index] = byte
                    }
                }
                
                let size = socklen_t(MemoryLayout<sockaddr_un>.size)
                let result = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(socket, $0, size)
                    }
                }
                
                if result == 0 {
                    isConnected = true
                    if handshake() {
                        return true
                    } else {
                        close(socket)
                        socket = -1
                        isConnected = false
                    }
                }
                
                close(socket)
            }
        }
        
        return false
    }
    
    private func handshake() -> Bool {
        let payload: [String: Any] = [
            "v": 1,
            "client_id": clientId
        ]
        
        guard sendFrame(opcode: .handshake, payload: payload) else {
            return false
        }
        
        if let response = readFrame() {
            if let cmd = response["cmd"] as? String,
               cmd == "DISPATCH",
               let evt = response["evt"] as? String,
               evt == "READY" {
                isReady = true
                return true
            }
        }
        
        return false
    }
    
    func setActivity(details: String, state: String, trackName: String, largeImage: String? = nil, largeText: String? = nil) -> Bool {
        guard isConnected && isReady else {
            return false
        }
        
        var activity: [String: Any] = [
            "type": 2,
            "name": trackName,
            "details": details,
            "state": state,
            "timestamps": [
                "start": Int(Date().timeIntervalSince1970)
            ]
        ]
        
        if let image = largeImage {
            var assets: [String: String] = ["large_image": image]
            if let text = largeText {
                assets["large_text"] = text
            }
            activity["assets"] = assets
        }
        
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "activity": activity
            ],
            "nonce": UUID().uuidString
        ]
        
        guard sendFrame(opcode: .frame, payload: payload) else {
            return false
        }
        
        if let response = readFrame() {
            if let evt = response["evt"] as? String, evt == "ERROR" {
                return false
            }
            return true
        }
        
        return false
    }
    
    func clearActivity() -> Bool {
        guard isConnected && isReady else { return false }
        
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "activity": NSNull()
            ],
            "nonce": UUID().uuidString
        ]
        
        return sendFrame(opcode: .frame, payload: payload)
    }
    
    private func sendFrame(opcode: Opcode, payload: [String: Any]) -> Bool {
        guard isConnected, socket != -1 else { return false }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            return false
        }
        
        var frame = Data()
        var op = opcode.rawValue.littleEndian
        var len = UInt32(jsonData.count).littleEndian
        
        frame.append(Data(bytes: &op, count: 4))
        frame.append(Data(bytes: &len, count: 4))
        frame.append(jsonData)
        
        let sent = frame.withUnsafeBytes { ptr in
            Darwin.send(socket, ptr.baseAddress, frame.count, 0)
        }
        
        if sent <= 0 {
            isConnected = false
            isReady = false
            return false
        }
        
        return sent == frame.count
    }
    
    private func readFrame() -> [String: Any]? {
        guard isConnected, socket != -1 else { return nil }
        
        var header = [UInt8](repeating: 0, count: 8)
        let headerRead = recv(socket, &header, 8, 0)
        
        guard headerRead == 8 else {
            if headerRead <= 0 {
                isConnected = false
                isReady = false
            }
            return nil
        }
        
        let headerData = Data(header)
        let length = headerData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self).littleEndian }
        
        guard length > 0 && length < 65536 else {
            return nil
        }
        
        var payload = [UInt8](repeating: 0, count: Int(length))
        let payloadRead = recv(socket, &payload, Int(length), 0)
        
        guard payloadRead == length else {
            return nil
        }
        
        let jsonData = Data(payload)
        
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        return json
    }
    
    func disconnect() {
        guard socket != -1 else { return }
        let sock = socket
        socket = -1
        isConnected = false
        isReady = false
        let _ = sendFrame(opcode: .close, payload: [:])
        close(sock)
    }
    
    deinit {
        disconnect()
    }
}

class MusicHelper {
    private static var artworkCache: [String: String] = [:]
    
    static func getCurrentTrack() -> (name: String, artist: String, album: String)? {
        let script = """
        tell application "Music"
            if player state is playing then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                return trackName & "|||" & trackArtist & "|||" & trackAlbum
            else
                return ""
            end if
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if let output = result.stringValue, !output.isEmpty {
                let parts = output.components(separatedBy: "|||")
                if parts.count == 3 {
                    return (parts[0], parts[1], parts[2])
                }
            }
        }
        return nil
    }
    
    static func getArtworkURL(track: String, artist: String, completion: @escaping (String?) -> Void) {
        let cacheKey = "\(track)-\(artist)"
        
        if let cachedURL = artworkCache[cacheKey] {
            completion(cachedURL)
            return
        }
        
        let searchTerm = "\(track) \(artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let urlString = "https://itunes.apple.com/search?term=\(searchTerm)&entity=song&limit=1"
        
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let artworkUrl = first["artworkUrl100"] as? String else {
                completion(nil)
                return
            }
            
            let highResUrl = artworkUrl.replacingOccurrences(of: "100x100", with: "512x512")
            artworkCache[cacheKey] = highResUrl
            completion(highResUrl)
        }
        
        task.resume()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var discord: DiscordRPC!
    var updateTimer: Timer?
    var reconnectTimer: Timer?
    var lastTrack: String = ""
    var isEnabled = true
    var isReconnecting = false
    let discordClientId = "1445087052608835676"
    let appBundleIdentifier = "com.ilnikk.MusicDiscordPresence"
    let currentVersion = "0.0.2"
    let githubRepo = "ilNikk/Apple-Music-Discord-Presence"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Music Discord Presence")
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        
        let statusMenuItem = NSMenuItem(title: "🔄 Connecting...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let toggleItem = NSMenuItem(title: "Enable Rich Presence", action: #selector(togglePresence), keyEquivalent: "t")
        toggleItem.state = .on
        toggleItem.tag = 101
        menu.addItem(toggleItem)
        
        let reconnectItem = NSMenuItem(title: "Reconnect to Discord", action: #selector(reconnectDiscord), keyEquivalent: "r")
        menu.addItem(reconnectItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let startAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        startAtLoginItem.tag = 102
        startAtLoginItem.state = isStartAtLoginEnabled() ? .on : .off
        menu.addItem(startAtLoginItem)
        
        let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "u")
        menu.addItem(checkUpdatesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
        
        discord = DiscordRPC(clientId: discordClientId)
        connectToDiscord()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updatePresence()
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
                    self?.updateStatusMenu("✅ Connected to Discord")
                    self?.updatePresence()
                } else {
                    self?.updateStatusMenu("❌ Discord not connected")
                    self?.scheduleReconnect()
                }
            }
        }
    }
    
    func scheduleReconnect() {
        guard reconnectTimer == nil else { return }
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.updateStatusMenu("🔄 Reconnecting...")
            self?.discord.disconnect()
            self?.isReconnecting = false
            self?.connectToDiscord()
        }
    }
    
    func handleConnectionLost() {
        discord.disconnect()
        lastTrack = ""
        updateStatusMenu("⚠️ Connection lost - Reconnecting...")
        scheduleReconnect()
    }
    
    @objc func reconnectDiscord() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        updateStatusMenu("🔄 Reconnecting...")
        discord.disconnect()
        lastTrack = ""
        isReconnecting = false
        connectToDiscord()
    }
    
    @objc func togglePresence() {
        isEnabled.toggle()
        
        if let menu = statusItem.menu,
           let toggleItem = menu.item(withTag: 101) {
            toggleItem.state = isEnabled ? .on : .off
        }
        
        if !isEnabled {
            _ = discord.clearActivity()
            updateStatusMenu("⏸ Presence disabled")
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
                
                if let menu = statusItem.menu,
                   let loginItem = menu.item(withTag: 102) {
                    loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
                }
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
                
                MusicHelper.getArtworkURL(track: track.name, artist: track.artist) { [weak self] artworkURL in
                    DispatchQueue.global(qos: .background).async {
                        let success = self?.discord.setActivity(
                            details: details,
                            state: state,
                            trackName: track.name,
                            largeImage: artworkURL,
                            largeText: track.album
                        ) ?? false
                        
                        DispatchQueue.main.async {
                            if success {
                                self?.updateStatusMenu("🎵 \(track.name) - \(track.artist)")
                            } else if self?.discord.isConnected == false {
                                self?.handleConnectionLost()
                            }
                        }
                    }
                }
            }
        } else {
            if !lastTrack.isEmpty {
                lastTrack = ""
                _ = discord.clearActivity()
                updateStatusMenu("⏹ No track playing")
            }
        }
    }
    
    func updateStatusMenu(_ text: String) {
        if let menu = statusItem.menu,
           let statusItem = menu.item(withTag: 100) {
            let maxLength = 40
            let displayText = text.count > maxLength ? String(text.prefix(maxLength)) + "..." : text
            statusItem.title = displayText
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
