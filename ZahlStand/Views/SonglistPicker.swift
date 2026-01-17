import SwiftUI

struct SonglistPicker: View {
    @EnvironmentObject var songlistService: SonglistService
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: DocumentViewerViewModel
    
    var body: some View {
        NavigationView {
            List {
                ForEach(songlistService.songlists) { songlist in
                    Button {
                        songlistService.setActiveSonglist(songlist)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(songlist.name).font(.headline)
                                Spacer()
                                Text("\(songlist.songCount) songs")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            if let event = songlist.event {
                                Text(event).font(.subheadline).foregroundColor(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }.foregroundColor(.primary)
                }
            }
            .navigationTitle("Select Songlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
