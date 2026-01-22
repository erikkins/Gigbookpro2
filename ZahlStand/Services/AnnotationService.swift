import Foundation
import UIKit
import Combine

/// Service for managing PDF annotations with local persistence
@MainActor
class AnnotationService: ObservableObject {
    @Published var currentStore: SongAnnotationStore?
    @Published var activeProfile: AnnotationProfile?

    private let annotationsDirectory: URL
    private let fileManager = FileManager.default

    /// Device name used as default owner for new profiles
    private var deviceOwnerName: String {
        UIDevice.current.name
    }

    init() {
        // Set up annotations directory in Documents/Annotations/
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        annotationsDirectory = documentsPath.appendingPathComponent("Annotations", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: annotationsDirectory.path) {
            try? fileManager.createDirectory(at: annotationsDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Storage Path

    private func storageURL(for songFileName: String) -> URL {
        let sanitized = songFileName.replacingOccurrences(of: "/", with: "_")
        return annotationsDirectory.appendingPathComponent("\(sanitized)_annotations.json")
    }

    // MARK: - Loading / Saving

    /// Load annotations for a song by its full file name (e.g., "MySong.pdf")
    func loadAnnotations(for songFileName: String) {
        let url = storageURL(for: songFileName)

        if fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let store = try JSONDecoder().decode(SongAnnotationStore.self, from: data)
                currentStore = store
                activeProfile = store.activeProfile
                let annotationCount = store.activeProfile?.annotations.count ?? 0
                print("📝 Loaded \(store.profiles.count) profiles for \(songFileName), active profile has \(annotationCount) annotations")
                return
            } catch {
                print("⚠️ Failed to decode annotations for \(songFileName): \(error)")
                // IMPORTANT: Do NOT overwrite the file if decoding fails
                // Keep the file intact so user data isn't lost
                // Just create an in-memory store without saving
                var store = SongAnnotationStore(songFileName: songFileName)
                let defaultProfile = AnnotationProfile(
                    name: "My Notes",
                    ownerName: deviceOwnerName,
                    isDefault: true
                )
                store.profiles = [defaultProfile]
                store.activeProfileId = defaultProfile.id
                currentStore = store
                activeProfile = defaultProfile
                // DO NOT call saveCurrentStore() here - preserve the original file
                return
            }
        }

        // Only create and save new store if file doesn't exist at all
        var store = SongAnnotationStore(songFileName: songFileName)
        let defaultProfile = AnnotationProfile(
            name: "My Notes",
            ownerName: deviceOwnerName,
            isDefault: true
        )
        store.profiles = [defaultProfile]
        store.activeProfileId = defaultProfile.id
        currentStore = store
        activeProfile = defaultProfile
        saveCurrentStore()
    }

    /// Save the current store to disk
    func saveCurrentStore() {
        guard var store = currentStore else { return }
        store.lastModified = Date()
        currentStore = store

        let url = storageURL(for: store.songFileName)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: url)
        }
    }

    /// Clear current annotations (when leaving a song)
    func clearCurrentAnnotations() {
        currentStore = nil
        activeProfile = nil
    }

    // MARK: - Profile Management

    /// Create a new annotation profile
    @discardableResult
    func createProfile(name: String, ownerName: String? = nil) -> AnnotationProfile {
        let profile = AnnotationProfile(name: name, ownerName: ownerName ?? deviceOwnerName)
        currentStore?.updateProfile(profile)
        saveCurrentStore()
        return profile
    }

    /// Set the active profile
    func setActiveProfile(_ profile: AnnotationProfile) {
        currentStore?.activeProfileId = profile.id
        activeProfile = profile
        saveCurrentStore()
    }

    /// Set active profile by ID
    func setActiveProfile(id: String) {
        currentStore?.activeProfileId = id
        activeProfile = currentStore?.profile(withId: id)
        saveCurrentStore()
    }

    /// Delete a profile
    func deleteProfile(_ profile: AnnotationProfile) {
        currentStore?.removeProfile(withId: profile.id)
        activeProfile = currentStore?.activeProfile
        saveCurrentStore()
    }

    /// Rename a profile
    func renameProfile(_ profile: AnnotationProfile, to newName: String) {
        guard var updatedProfile = currentStore?.profile(withId: profile.id) else { return }
        updatedProfile.name = newName
        updatedProfile.modifiedAt = Date()
        currentStore?.updateProfile(updatedProfile)
        if activeProfile?.id == profile.id {
            activeProfile = updatedProfile
        }
        saveCurrentStore()
    }

    // MARK: - Annotation CRUD

    /// Add a new annotation to the active profile
    func addAnnotation(_ annotation: PDFAnnotation) {
        guard var profile = activeProfile else { return }
        profile.annotations.append(annotation)
        profile.modifiedAt = Date()
        currentStore?.updateProfile(profile)
        activeProfile = profile
        saveCurrentStore()
    }

    /// Update an existing annotation
    func updateAnnotation(_ annotation: PDFAnnotation) {
        guard var profile = activeProfile,
              let index = profile.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }

        var updated = annotation
        updated.modifiedAt = Date()
        profile.annotations[index] = updated
        profile.modifiedAt = Date()
        currentStore?.updateProfile(profile)
        activeProfile = profile
        saveCurrentStore()
    }

    /// Delete an annotation
    func deleteAnnotation(_ annotation: PDFAnnotation) {
        guard var profile = activeProfile else { return }
        profile.annotations.removeAll { $0.id == annotation.id }
        profile.modifiedAt = Date()
        currentStore?.updateProfile(profile)
        activeProfile = profile
        saveCurrentStore()
    }

    /// Get annotations for a specific page in the active profile
    func annotations(forPage pageIndex: Int) -> [PDFAnnotation] {
        activeProfile?.annotations(forPage: pageIndex) ?? []
    }

    /// Get all annotations in the active profile
    var allAnnotations: [PDFAnnotation] {
        activeProfile?.annotations ?? []
    }

    // MARK: - Export / Import (for cloud sync)

    /// Export all profiles for a song (used when uploading songlist)
    func exportProfiles() -> [AnnotationProfile] {
        currentStore?.profiles ?? []
    }

    /// Import profiles from cloud data
    func importProfiles(_ profiles: [AnnotationProfile], merge: Bool) {
        guard var store = currentStore else { return }

        if merge {
            // Merge: update existing profiles, add new ones
            for importedProfile in profiles {
                if let existingIndex = store.profiles.firstIndex(where: { $0.id == importedProfile.id }) {
                    // Keep the more recently modified version
                    if importedProfile.modifiedAt > store.profiles[existingIndex].modifiedAt {
                        store.profiles[existingIndex] = importedProfile
                    }
                } else {
                    store.profiles.append(importedProfile)
                }
            }
        } else {
            // Replace: use imported profiles entirely
            store.profiles = profiles
            // Try to keep the same active profile if it exists
            if let activeId = store.activeProfileId,
               !profiles.contains(where: { $0.id == activeId }) {
                store.activeProfileId = profiles.first?.id
            }
        }

        currentStore = store
        activeProfile = store.activeProfile
        saveCurrentStore()
    }

    // MARK: - Utility

    /// Check if any annotations exist for the current song
    var hasAnnotations: Bool {
        guard let store = currentStore else { return false }
        return store.profiles.contains { !$0.annotations.isEmpty }
    }

    /// Get all available profiles
    var availableProfiles: [AnnotationProfile] {
        currentStore?.profiles ?? []
    }
}
