# File Storage Guide - ZahlStand Swift

## 📁 Where Are Song Files Stored?

### **Important: Song files are NOT in the Xcode project!**

Song files (PDFs, DOCs) are stored in the **iPad's Documents directory** at runtime, not in the project bundle. This is the correct approach for user-generated content.

## 📍 File Locations

### During Development (Simulator)
```
~/Library/Developer/CoreSimulator/Devices/[DEVICE-ID]/data/Containers/Data/Application/[APP-ID]/Documents/
├── Music/              ← PDF and DOC files imported by user
│   ├── song1.pdf
│   ├── song2.pdf
│   └── sheet_music.doc
└── Songlists/          ← JSON files for songlists
    ├── Concert_2024.json
    └── Practice_Set.json
```

### On Real iPad
```
[App Container]/Documents/
├── Music/              ← Your imported songs
└── Songlists/          ← Your created songlists
```

## 🔄 How File Storage Works

### 1. **Importing Files (User Action)**
When a user taps the **+ button** and selects PDF/DOC files:

```swift
// In DocumentService.swift
func importDocument(from url: URL, completion: ...) {
    // File is copied from user's selection to:
    // Documents/Music/filename.pdf
    
    let destination = musicDirectory.appendingPathComponent(fileName)
    try fileManager.copyItem(at: url, to: destination)
}
```

**User flow:**
1. Tap + button
2. Select files from Files app, iCloud Drive, etc.
3. Files are **copied** into app's Documents/Music folder
4. App reads from there forever after

### 2. **Creating Songlists**
When a user creates a songlist:

```swift
// In SonglistService.swift
func saveSonglist(_ songlist: Songlist) throws {
    // Saves JSON file to:
    // Documents/Songlists/Concert_Name.json
    
    let url = songlistsDirectory.appendingPathComponent("\(songlist.name).json")
    try data.write(to: url)
}
```

### 3. **Loading Songs**
On app launch:

```swift
// In DocumentService.swift - called in init()
func loadSongs() {
    // Scans Documents/Music/ for all PDF/DOC files
    // Creates Song objects from found files
    // Displays in song library
}
```

## 📤 Testing File Import

### In Simulator:

1. **Build and run the app**
2. **Add sample PDFs** two ways:

   **Option A: Drag & Drop to Simulator**
   - Drag PDF files directly onto simulator
   - They go to Files app
   - In ZahlStand, tap + → select from Files

   **Option B: Add to Simulator manually**
   ```bash
   # Find simulator path
   xcrun simctl get_app_container booted com.zahlstand.app data
   
   # Copy test files
   cp ~/Desktop/test.pdf "[RESULT]/Documents/Music/"
   ```

3. **Restart app** - songs appear automatically!

### On Real iPad:

1. **Build to iPad**
2. **Import from anywhere:**
   - iCloud Drive
   - Files app
   - Email attachments
   - AirDrop
   - Cloud storage (Dropbox, etc.)

## 🎵 Sample Test Files

Create these test files to try it out:

```bash
# Create sample PDFs on Mac
cd ~/Desktop

# Create a simple PDF
echo "Test Sheet Music" | textutil -convert pdf -stdin -output song1.pdf

# Create another
echo "Another Song" | textutil -convert pdf -stdin -output song2.pdf
```

Then drag these to simulator or import via Files app!

## 🔍 Finding Your Files (Debugging)

### View Simulator Files:
```bash
# Get app container path
xcrun simctl get_app_container booted com.zahlstand.app data

# List music files
ls -la "[RESULT]/Documents/Music/"

# List songlists
ls -la "[RESULT]/Documents/Songlists/"
```

### View on iPad:
- Files app → On My iPad → ZahlStand

## ☁️ Azure Cloud Storage

Songlists (not the PDF files themselves) can be synced to Azure:

```
Local:  Documents/Songlists/Concert.json
  ↓
Azure:  [container]/Concert.json
  ↓
Other iPad: Documents/Songlists/Concert.json
```

**Note:** Only the **songlist metadata** is synced, not the actual PDF files. This is intentional - PDFs would be too large for efficient sync.

## 💡 Why This Design?

### ✅ Advantages:
1. **User Privacy** - Files stay in app container
2. **Efficient** - No bundling large PDFs in app
3. **Dynamic** - Users add their own content
4. **Standard iOS** - Uses system file picker
5. **Backup** - Files backed up with iTunes/iCloud

### ❌ Not Stored in Project Bundle Because:
- User files shouldn't be in app bundle
- App bundle is read-only after installation
- Each user has different songs
- Would bloat app download size

## 📝 Summary

**Song Files:**
- Location: `Documents/Music/` (created at runtime)
- Source: User imports via file picker
- Format: PDF, DOC, DOCX
- Not in Xcode project ✓

**Songlist Files:**
- Location: `Documents/Songlists/` (created at runtime)
- Source: User creates in app
- Format: JSON
- Not in Xcode project ✓

**App Code:**
- Location: Xcode project (all .swift files)
- Source: This package
- What you're building ✓

This is the **standard iOS app architecture** for user-generated content!
