import SwiftUI

struct ContentView: View {
    @State private var videoLibrary = VideoLibrary()

    var body: some View {
        TabView {
            CameraView(videoLibrary: videoLibrary)
                .tabItem {
                    Label("カメラ", systemImage: "camera.fill")
                }

            VideoListView(videoLibrary: videoLibrary)
                .tabItem {
                    Label("一覧", systemImage: "list.bullet")
                }
        }
    }
}

#Preview {
    ContentView()
}
