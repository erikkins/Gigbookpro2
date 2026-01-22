import SwiftUI

/// Profile picker and management UI for annotation profiles
struct AnnotationProfilePicker: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var annotationService: AnnotationService

    @State private var showingNewProfile = false
    @State private var newProfileName = ""
    @State private var profileToRename: AnnotationProfile?
    @State private var renameText = ""

    var body: some View {
        NavigationView {
            List {
                Section("Profiles") {
                    ForEach(annotationService.availableProfiles) { profile in
                        profileRow(for: profile)
                    }
                    .onDelete(perform: deleteProfiles)
                }

                Section {
                    Button {
                        showingNewProfile = true
                    } label: {
                        Label("New Profile", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Annotation Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("New Profile", isPresented: $showingNewProfile) {
                TextField("Profile Name", text: $newProfileName)
                Button("Cancel", role: .cancel) {
                    newProfileName = ""
                }
                Button("Create") {
                    createProfile()
                }
            } message: {
                Text("Enter a name for the new annotation profile.")
            }
            .alert("Rename Profile", isPresented: .init(
                get: { profileToRename != nil },
                set: { if !$0 { profileToRename = nil } }
            )) {
                TextField("Profile Name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    profileToRename = nil
                    renameText = ""
                }
                Button("Rename") {
                    renameProfile()
                }
            } message: {
                Text("Enter a new name for the profile.")
            }
        }
    }

    private func profileRow(for profile: AnnotationProfile) -> some View {
        Button {
            annotationService.setActiveProfile(profile)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(profile.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if profile.isDefault {
                            Text("Default")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 8) {
                        let count = profile.annotations.count
                        Text("\(count) annotation\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let ownerName = profile.ownerName {
                            Text("by \(ownerName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                }

                Spacer()

                if annotationService.activeProfile?.id == profile.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .font(.body.bold())
                }
            }
        }
        .contextMenu {
            Button {
                profileToRename = profile
                renameText = profile.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            if !profile.isDefault {
                Button(role: .destructive) {
                    annotationService.deleteProfile(profile)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func deleteProfiles(at offsets: IndexSet) {
        let profiles = annotationService.availableProfiles
        for index in offsets {
            let profile = profiles[index]
            if !profile.isDefault {
                annotationService.deleteProfile(profile)
            }
        }
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            newProfileName = ""
            return
        }

        let profile = annotationService.createProfile(name: name)
        annotationService.setActiveProfile(profile)
        newProfileName = ""
        dismiss()
    }

    private func renameProfile() {
        guard let profile = profileToRename else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            profileToRename = nil
            renameText = ""
            return
        }

        annotationService.renameProfile(profile, to: name)
        profileToRename = nil
        renameText = ""
    }
}
