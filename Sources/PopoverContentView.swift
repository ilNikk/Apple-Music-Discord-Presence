import Cocoa

class HoverButton: NSButton {
    var normalColor: NSColor = .clear
    var hoverColor: NSColor = .quaternaryLabelColor
    var isRed = false
    
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        wantsLayer = true
        layer?.backgroundColor = hoverColor.cgColor
        layer?.cornerRadius = 6
    }
    
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = normalColor.cgColor
    }
}

class PopoverContentView: NSView {
    var trackLabel: NSTextField!
    var artistLabel: NSTextField!
    var albumLabel: NSTextField!
    var albumArtView: NSImageView!
    var enableToggle: NSSwitch!
    var startAtLoginToggle: NSSwitch!
    
    weak var delegate: AppDelegate?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        wantsLayer = true
        
        albumArtView = NSImageView(frame: .zero)
        albumArtView.translatesAutoresizingMaskIntoConstraints = false
        albumArtView.imageScaling = .scaleProportionallyUpOrDown
        albumArtView.wantsLayer = true
        albumArtView.layer?.cornerRadius = 8
        albumArtView.layer?.masksToBounds = true
        albumArtView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        addSubview(albumArtView)
        
        trackLabel = NSTextField(labelWithString: "No track playing")
        trackLabel.translatesAutoresizingMaskIntoConstraints = false
        trackLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        trackLabel.textColor = .labelColor
        trackLabel.lineBreakMode = .byTruncatingTail
        addSubview(trackLabel)
        
        artistLabel = NSTextField(labelWithString: "")
        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        artistLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.lineBreakMode = .byTruncatingTail
        addSubview(artistLabel)
        
        albumLabel = NSTextField(labelWithString: "")
        albumLabel.translatesAutoresizingMaskIntoConstraints = false
        albumLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        albumLabel.textColor = .tertiaryLabelColor
        albumLabel.lineBreakMode = .byTruncatingTail
        addSubview(albumLabel)
        
        let separator1 = NSBox()
        separator1.translatesAutoresizingMaskIntoConstraints = false
        separator1.boxType = .separator
        addSubview(separator1)
        
        let enableLabel = NSTextField(labelWithString: "Enable Rich Presence")
        enableLabel.translatesAutoresizingMaskIntoConstraints = false
        enableLabel.font = NSFont.systemFont(ofSize: 13)
        addSubview(enableLabel)
        
        enableToggle = NSSwitch()
        enableToggle.translatesAutoresizingMaskIntoConstraints = false
        enableToggle.state = .on
        enableToggle.target = self
        enableToggle.action = #selector(togglePresence)
        addSubview(enableToggle)
        
        let loginLabel = NSTextField(labelWithString: "Start at Login")
        loginLabel.translatesAutoresizingMaskIntoConstraints = false
        loginLabel.font = NSFont.systemFont(ofSize: 13)
        addSubview(loginLabel)
        
        startAtLoginToggle = NSSwitch()
        startAtLoginToggle.translatesAutoresizingMaskIntoConstraints = false
        startAtLoginToggle.target = self
        startAtLoginToggle.action = #selector(toggleStartAtLogin)
        addSubview(startAtLoginToggle)
        
        let separator2 = NSBox()
        separator2.translatesAutoresizingMaskIntoConstraints = false
        separator2.boxType = .separator
        addSubview(separator2)
        
        let reconnectButton = createButton(title: "Reconnect to Discord", action: #selector(reconnectDiscord))
        let updateButton = createButton(title: "Check for Updates...", action: #selector(checkForUpdates))
        let quitButton = createButton(title: "Quit", action: #selector(quit), isRed: true)
        
        NSLayoutConstraint.activate([
            albumArtView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            albumArtView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            albumArtView.widthAnchor.constraint(equalToConstant: 64),
            albumArtView.heightAnchor.constraint(equalToConstant: 64),
            
            trackLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            trackLabel.leadingAnchor.constraint(equalTo: albumArtView.trailingAnchor, constant: 12),
            trackLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            artistLabel.topAnchor.constraint(equalTo: trackLabel.bottomAnchor, constant: 2),
            artistLabel.leadingAnchor.constraint(equalTo: albumArtView.trailingAnchor, constant: 12),
            artistLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            albumLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 2),
            albumLabel.leadingAnchor.constraint(equalTo: albumArtView.trailingAnchor, constant: 12),
            albumLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            separator1.topAnchor.constraint(equalTo: albumArtView.bottomAnchor, constant: 16),
            separator1.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            separator1.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            enableLabel.topAnchor.constraint(equalTo: separator1.bottomAnchor, constant: 12),
            enableLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            
            enableToggle.centerYAnchor.constraint(equalTo: enableLabel.centerYAnchor),
            enableToggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            loginLabel.topAnchor.constraint(equalTo: enableLabel.bottomAnchor, constant: 12),
            loginLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            
            startAtLoginToggle.centerYAnchor.constraint(equalTo: loginLabel.centerYAnchor),
            startAtLoginToggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            separator2.topAnchor.constraint(equalTo: loginLabel.bottomAnchor, constant: 12),
            separator2.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            separator2.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            reconnectButton.topAnchor.constraint(equalTo: separator2.bottomAnchor, constant: 8),
            reconnectButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            reconnectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            reconnectButton.heightAnchor.constraint(equalToConstant: 28),
            
            updateButton.topAnchor.constraint(equalTo: reconnectButton.bottomAnchor, constant: 2),
            updateButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            updateButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            updateButton.heightAnchor.constraint(equalToConstant: 28),
            
            quitButton.topAnchor.constraint(equalTo: updateButton.bottomAnchor, constant: 2),
            quitButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            quitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            quitButton.heightAnchor.constraint(equalToConstant: 28),
            quitButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }
    
    private func createButton(title: String, action: Selector, isRed: Bool = false) -> HoverButton {
        let button = HoverButton(title: "  \(title)", target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .recessed
        button.isBordered = false
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 13)
        button.contentTintColor = isRed ? .systemRed : .labelColor
        button.isRed = isRed
        addSubview(button)
        return button
    }
    
    func updateTrackInfo(track: String?, artist: String?, album: String?, artwork: NSImage?) {
        if let track = track, let artist = artist {
            trackLabel.stringValue = track
            artistLabel.stringValue = artist
            albumLabel.stringValue = album ?? ""
            if let art = artwork {
                albumArtView.image = art
            }
        } else {
            trackLabel.stringValue = "No track playing"
            artistLabel.stringValue = ""
            albumLabel.stringValue = ""
            albumArtView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        }
    }
    
    func updateStatus(_ text: String) {
        // Status rimosso dalla UI
    }
    
    func updateLoginToggle(_ enabled: Bool) {
        startAtLoginToggle.state = enabled ? .on : .off
    }
    
    @objc private func togglePresence() {
        delegate?.togglePresence()
    }
    
    @objc private func toggleStartAtLogin() {
        delegate?.toggleStartAtLogin()
    }
    
    @objc private func reconnectDiscord() {
        delegate?.reconnectDiscord()
    }
    
    @objc private func checkForUpdates() {
        delegate?.checkForUpdates()
    }
    
    @objc private func quit() {
        delegate?.quit()
    }
}
