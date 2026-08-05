import AVKit
import SwiftUI

struct VideoPlayerScreen: View {
    let video: VideoItem
    @State private var player: AVPlayer

    init(video: VideoItem) {
        self.video = video
        _player = State(initialValue: AVPlayer(url: video.url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .navigationTitle(video.createdAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}
