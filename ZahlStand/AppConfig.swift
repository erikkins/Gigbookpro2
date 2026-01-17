import Foundation

struct AppConfig {
    // MARK: - Azure Storage Configuration
    static let azureAccountName = "zahl"
    static let azureAccountKey = "JgQpOvBcyNZBJBrjjtBupJogwFK5KndZ2wYay9WxMRW1CKMkLFTvOx2RPolkKV0ccLMTcad6eIDzW/rKEwjoWQ=="  // Add your key here
    static let azureLegacyContainer = "playlists"          // Existing legacy blobs
    static let azureNewContainer = "songlists-v2"          // New format songlists
    
    // MARK: - App Settings
    static let musicDirectoryName = "Music"
    static let songlistsDirectoryName = "Songlists"
    static let maxFileSize: Int64 = 50 * 1024 * 1024 // 50MB
    static let supportedExtensions = ["pdf", "doc", "docx"]
    
    // MARK: - MIDI Settings
    static let midiEnabled = true
    static let midiClientName = "ZahlStand MIDI Client"
    
    // MARK: - Peer Connectivity
    static let peerServiceType = "zahlstand"
    static let autoAcceptPeerInvitations = true
}
