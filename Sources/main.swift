import Cocoa

class DiscordRPC {
    private var socket: Int32 = -1
    private let clientId: String
    private var isConnected = false
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
        
        return sent == frame.count
    }
    
    private func readFrame() -> [String: Any]? {
        var header = [UInt8](repeating: 0, count: 8)
        let headerRead = recv(socket, &header, 8, 0)
        
        guard headerRead == 8 else {
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
        if socket != -1 {
            let _ = sendFrame(opcode: .close, payload: [:])
            close(socket)
            socket = -1
            isConnected = false
            isReady = false
        }
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
    var lastTrack: String = ""
    var isEnabled = true
    let discordClientId = "1445087052608835676"
    
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
        
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
        
        discord = DiscordRPC(clientId: discordClientId)
        connectToDiscord()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updatePresence()
        }
    }
    
    func connectToDiscord() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            let connected = self?.discord.connect() ?? false
            DispatchQueue.main.async {
                if connected {
                    self?.updateStatusMenu("✅ Connected to Discord")
                    self?.updatePresence()
                } else {
                    self?.updateStatusMenu("❌ Discord not connected")
                }
            }
        }
    }
    
    @objc func reconnectDiscord() {
        updateStatusMenu("🔄 Reconnecting...")
        discord.disconnect()
        lastTrack = ""
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
        _ = discord.clearActivity()
        discord.disconnect()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
