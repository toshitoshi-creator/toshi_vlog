import SwiftUI

struct VideoListView: View {
    let videoLibrary: VideoLibrary

    var body: some View {
        NavigationStack {
            Group {
                if videoLibrary.videos.isEmpty {
                    ContentUnavailableView(
                        "動画がありません",
                        systemImage: "video.slash",
                        description: Text("カメラタブで撮影すると、ここに一覧表示されます")
                    )
                } else {
                    List {
                        ForEach(videoLibrary.videos) { video in
                            NavigationLink {
                                VideoPlayerScreen(video: video)
                            } label: {
                                VideoRowView(video: video)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("撮影した動画")
            .task {
                await videoLibrary.reload()
            }
            .refreshable {
                await videoLibrary.reload()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let video = videoLibrary.videos[index]
            Task { await videoLibrary.delete(video) }
        }
    }
}
