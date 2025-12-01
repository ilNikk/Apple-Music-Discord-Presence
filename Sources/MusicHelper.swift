import Cocoa

class MusicHelper {
    private static var artworkCache: [String: String] = [:]
    private static var imageCache: [String: NSImage] = [:]
    
    static func getCurrentTrack() -> (name: String, artist: String, album: String, storeID: String?)? {
        let script = """
        tell application "Music"
            if player state is playing then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackStoreID to ""
                try
                    -- Get the persistent ID or database ID
                    set dbID to database ID of current track
                    set trackStoreID to dbID as string
                end try
                return trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & trackStoreID
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
                if parts.count >= 3 {
                    let storeID = parts.count >= 4 && !parts[3].isEmpty ? parts[3] : nil
                    return (parts[0], parts[1], parts[2], storeID)
                }
            }
        }
        return nil
    }
    
    static func getLocalArtwork() -> NSImage? {
        let script = """
        tell application "Music"
            if player state is playing then
                try
                    set artworkData to raw data of artwork 1 of current track
                    return artworkData
                on error
                    return missing value
                end try
            else
                return missing value
            end if
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            let data = result.data
            return NSImage(data: data)
        }
        return nil
    }
    
    static func getArtworkURL(track: String, artist: String, album: String, storeID: String?, completion: @escaping (String?) -> Void) {
        // First try with store ID if available (most accurate)
        if let storeID = storeID, !storeID.isEmpty {
            let lookupURL = "https://itunes.apple.com/lookup?id=\(storeID)"
            
            if let url = URL(string: lookupURL) {
                let task = URLSession.shared.dataTask(with: url) { data, response, error in
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = json["results"] as? [[String: Any]],
                       let first = results.first,
                       let artworkUrl = first["artworkUrl100"] as? String {
                        let highResUrl = artworkUrl.replacingOccurrences(of: "100x100", with: "512x512")
                        completion(highResUrl)
                        return
                    }
                    // Fallback to search if lookup fails
                    self.searchArtwork(track: track, artist: artist, album: album, completion: completion)
                }
                task.resume()
                return
            }
        }
        
        // Fallback: search by track name + artist (more accurate than album search)
        searchArtwork(track: track, artist: artist, album: album, completion: completion)
    }
    
    private static func searchArtwork(track: String, artist: String, album: String, completion: @escaping (String?) -> Void) {
        let cacheKey = "\(track)-\(artist)"
        
        if let cachedURL = artworkCache[cacheKey] {
            completion(cachedURL)
            return
        }
        
        // Search by track + artist for more accurate results
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
