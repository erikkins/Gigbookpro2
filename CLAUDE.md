# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Open in Xcode
open ZahlStand.xcodeproj

# Build from command line
xcodebuild -project ZahlStand.xcodeproj -scheme ZahlStand -configuration Debug

# Build for simulator
xcodebuild -project ZahlStand.xcodeproj -scheme ZahlStand -destination 'platform=iOS Simulator,name=iPad Pro'
```

No CocoaPods, SPM, or external dependencies - the project uses only system frameworks.

## Architecture

**ZahlStand** is an iPad music stand app for displaying sheet music (PDF/Word) during performances. It's a complete Swift rewrite of a legacy Objective-C app.

### Data Flow (MVVM + Services)
```
Models (Song, Songlist) → Services (business logic) → ViewModels (state) → Views (SwiftUI)
```

### Key Services
- **DocumentService** - File management, PDF/DOC import, song metadata. Stores files in `Documents/Music/`
- **SonglistService** - Setlist CRUD. Each songlist is a separate JSON file in `Documents/Songlists/`
- **MIDIService** - CoreMIDI wrapper for foot pedal control (default: C4=next, B3=previous)
- **AzureStorageService** - Cloud sync via REST API (requires credentials in AppConfig.swift)
- **PeerConnectivityService** - Device-to-device sharing via MultipeerConnectivity

### Model Relationships
- `Song` contains file metadata + MIDI program change settings
- `Songlist` references songs by ID (not embedded), with a transient weak reference to DocumentService for runtime lookups

### Concurrency Model
All models and services use `@MainActor`. Network/file I/O uses async/await. State updates via `@Published` + Combine.

## Important Patterns

**Service initialization**: Services are `@StateObject` in `ZahlStandApp.swift` and passed via `@EnvironmentObject`

**File storage paths**:
- Song files: `Documents/Music/`
- Songlist JSON: `Documents/Songlists/[id].json`
- Song metadata cache: `Documents/songs_metadata.json`

**Bundled content**: 419 sample songs in `BundledSongs/` copied to Documents on first launch

**iOS version handling**: Uses `NavigationView` for iOS 15, `NavigationSplitView` for iOS 16+

## Configuration

`AppConfig.swift` contains:
- Azure credentials (account name, key, container names)
- Directory names and file size limits
- Supported file extensions: pdf, doc, docx
- MIDI client name and peer service type

## Known Build Considerations

- Deployment target: iOS 15.0+
- Swift 5.10+ / Xcode 15.0+
- iPad optimized (iPhone supported with portrait fallback)
- MIDIPacketList uses `UnsafePointer<MIDIPacketList>` (not direct type)
- `deinit` cleanup must be synchronous (no async calls)
