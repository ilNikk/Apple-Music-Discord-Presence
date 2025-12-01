import Foundation

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
