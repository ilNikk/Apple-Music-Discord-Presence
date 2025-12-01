# 🎵 Music Discord Presence

A lightweight macOS menu bar app that displays your currently playing Apple Music track as Discord Rich Presence.

![macOS](https://img.shields.io/badge/macOS-12.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## ✨ Features

- 🎧 Shows "Listening to" on Discord (like Spotify!)
- 🖼️ Automatically fetches album artwork from iTunes
- 📍 Lives in your menu bar - no dock icon, no windows
- 🔄 Updates automatically when track changes
- ⚡ Lightweight and native Swift implementation

## 📸 Preview

Your Discord profile will show:
- "Listening to [Track Name]"
- Artist name
- Album artwork
- Album name (on hover)

## 🚀 Installation

### Build from Source

1. Clone the repository:
```bash
git clone https://github.com/YOUR_USERNAME/MusicDiscordPresence.git
cd MusicDiscordPresence
```

2. Build the app:
```bash
swift build -c release
```

3. Run it:
```bash
.build/release/MusicDiscordPresence
```

## 🎮 Usage

1. Make sure Discord desktop app is running
2. Launch MusicDiscordPresence
3. Play music in Apple Music
4. Your Discord status will automatically update!

### Menu Bar Options

Click the 🎵 icon in your menu bar:

- **Toggle Rich Presence** - Enable/disable the Discord status
- **Reconnect to Discord** - Manually reconnect if disconnected
- **Quit** - Exit the application

## ⚙️ Requirements

- macOS 12.0 or later
- Discord desktop app (not browser version)
- Apple Music

## 🚀 Run at Login (Optional)

To have the app start automatically:

1. Open **System Settings** → **General** → **Login Items**
2. Click **+** and add the MusicDiscordPresence binary

## 🛠️ How It Works

1. Connects to Discord via IPC socket
2. Monitors Apple Music playback via AppleScript
3. Fetches album artwork from iTunes Search API
4. Updates Discord Rich Presence every 5 seconds

## 🤝 Contributing

Contributions are welcome! Feel free to:

- Report bugs
- Suggest features  
- Submit pull requests

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This project is not affiliated with Apple or Discord. Apple Music is a trademark of Apple Inc. Discord is a trademark of Discord Inc.
