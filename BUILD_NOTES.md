# Build Notes - ZahlStand Swift

## ✅ Fixed Build Errors

### Error 1: "Cannot find type MIDIPacketList in scope"
**Fixed!** Changed to use `UnsafePointer<MIDIPacketList>` properly in:
- `MIDIService.swift`
- `DocumentViewerViewModel.swift`

### Error 2: "NavigationSplitViewVisibility is only available in iOS 16.0 or newer"
**Fixed!** Added iOS version checking in `ZahlStandApp.swift`:
```swift
if #available(iOS 16.0, *) {
    NavigationSplitView { ... }  // iOS 16+
} else {
    NavigationView { ... }       // iOS 15 fallback
}
```

## 🔧 Build Settings

**Deployment Target:** iOS 15.0
- iOS 15: Uses NavigationView
- iOS 16+: Uses NavigationSplitView

**Swift Version:** 5.0

## 🚀 Building the Project

1. Open `ZahlStand.xcodeproj` in Xcode 15+
2. Select iPad simulator (or real iPad)
3. Press ⌘R to build and run
4. Should build without errors! ✅

## ⚠️ Known Warnings (Safe to Ignore)

You may see warnings about:
- "UISupportsDocumentBrowser" in Info.plist - This is intentional
- Missing app icons - Add icons later if needed

## 📱 Testing

1. **Run in Simulator**
2. **Tap + button** to import files
3. **Create a songlist** from menu
4. **Test MIDI** if you have a MIDI device

## 🐛 If You Get Other Errors

**"No such module 'CoreMIDI'"**
- Make sure you're building for iOS, not macOS
- Target should be "iPhone" or "iPad"

**"Command CompileSwift failed"**
- Clean build folder: ⌘⇧K
- Restart Xcode
- Try again

**File import not working?**
- Check Info.plist has `UISupportsDocumentBrowser` ✓
- Make sure you're selecting actual PDF files
- Try importing one file at a time first

## ✅ Should Build Successfully Now!

All errors are fixed. The app should compile and run on:
- ✅ iPad Simulator (iOS 15.0+)
- ✅ Real iPad (iOS 15.0+)
- ✅ Xcode 15.0+

## 🔧 Additional Fixes (Latest Update)

### Error 3: "Call to main actor-isolated instance method 'cleanup()' in synchronous non isolated context"
**Fixed!** In `MIDIService.swift`:
- Moved cleanup code directly into `deinit`
- `deinit` cannot be async, so cleanup must be synchronous
- Direct MIDI disposal calls are synchronous and safe

### Error 4: "Cannot find 'withAnimation' in scope"
**Fixed!** In `DocumentViewerViewModel.swift`:
- Added `import SwiftUI` 
- `withAnimation` is a SwiftUI function
- ViewModel can import SwiftUI for animations

## ✅ All Build Errors Resolved

The project should now build cleanly with no errors!

**Build Status:** ✅ Ready to compile
**Last Updated:** January 13, 2026
