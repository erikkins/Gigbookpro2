import Foundation
import SwiftUI

// MARK: - Annotation Color

enum AnnotationColor: String, Codable, CaseIterable, Identifiable {
    case yellow
    case red
    case blue
    case green
    case orange
    case purple

    var id: String { rawValue }

    var uiColor: Color {
        switch self {
        case .yellow: return .yellow
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Annotation Font Size

enum AnnotationFontSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var font: Font {
        switch self {
        case .small: return .caption
        case .medium: return .subheadline
        case .large: return .body
        }
    }
}

// MARK: - PDF Annotation

struct PDFAnnotation: Codable, Identifiable, Equatable {
    var id: String
    var pageIndex: Int                    // 0-based page number
    var relativeX: CGFloat                // 0.0 - 1.0 (percentage of page width)
    var relativeY: CGFloat                // 0.0 - 1.0 (percentage of page height)
    var text: String
    var color: AnnotationColor
    var fontSize: AnnotationFontSize
    var isBold: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(id: String = UUID().uuidString,
         pageIndex: Int,
         relativeX: CGFloat,
         relativeY: CGFloat,
         text: String,
         color: AnnotationColor = .yellow,
         fontSize: AnnotationFontSize = .small,
         isBold: Bool = false,
         createdAt: Date = Date(),
         modifiedAt: Date = Date()) {
        self.id = id
        self.pageIndex = pageIndex
        self.relativeX = relativeX
        self.relativeY = relativeY
        self.text = text
        self.color = color
        self.fontSize = fontSize
        self.isBold = isBold
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    static func == (lhs: PDFAnnotation, rhs: PDFAnnotation) -> Bool {
        lhs.id == rhs.id
    }

    // Custom decoder for backward compatibility with existing annotations
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        pageIndex = try container.decode(Int.self, forKey: .pageIndex)
        relativeX = try container.decode(CGFloat.self, forKey: .relativeX)
        relativeY = try container.decode(CGFloat.self, forKey: .relativeY)
        text = try container.decode(String.self, forKey: .text)
        color = try container.decode(AnnotationColor.self, forKey: .color)
        // Provide defaults for new fields that may not exist in old data
        fontSize = try container.decodeIfPresent(AnnotationFontSize.self, forKey: .fontSize) ?? .small
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, pageIndex, relativeX, relativeY, text, color, fontSize, isBold, createdAt, modifiedAt
    }
}

// MARK: - Annotation Profile

struct AnnotationProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String                      // "My Notes", "Band Leader"
    var ownerName: String?                // Who created this
    var isDefault: Bool
    var annotations: [PDFAnnotation]
    var createdAt: Date
    var modifiedAt: Date

    init(id: String = UUID().uuidString,
         name: String,
         ownerName: String? = nil,
         isDefault: Bool = false,
         annotations: [PDFAnnotation] = [],
         createdAt: Date = Date(),
         modifiedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.ownerName = ownerName
        self.isDefault = isDefault
        self.annotations = annotations
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    static func == (lhs: AnnotationProfile, rhs: AnnotationProfile) -> Bool {
        lhs.id == rhs.id
    }

    /// Get annotations for a specific page
    func annotations(forPage pageIndex: Int) -> [PDFAnnotation] {
        annotations.filter { $0.pageIndex == pageIndex }
    }
}

// MARK: - Song Annotation Store

/// Container for all annotation profiles for a single song
struct SongAnnotationStore: Codable {
    var songFileName: String              // Cross-device stable key (e.g., "MySong.pdf")
    var profiles: [AnnotationProfile]
    var activeProfileId: String?
    var lastModified: Date

    init(songFileName: String,
         profiles: [AnnotationProfile] = [],
         activeProfileId: String? = nil,
         lastModified: Date = Date()) {
        self.songFileName = songFileName
        self.profiles = profiles
        self.activeProfileId = activeProfileId
        self.lastModified = lastModified
    }

    /// Get the currently active profile
    var activeProfile: AnnotationProfile? {
        guard let activeId = activeProfileId else {
            return profiles.first { $0.isDefault } ?? profiles.first
        }
        return profiles.first { $0.id == activeId }
    }

    /// Get profile by ID
    func profile(withId id: String) -> AnnotationProfile? {
        profiles.first { $0.id == id }
    }

    /// Update or add a profile
    mutating func updateProfile(_ profile: AnnotationProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        lastModified = Date()
    }

    /// Remove a profile by ID
    mutating func removeProfile(withId id: String) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles.first?.id
        }
        lastModified = Date()
    }
}
