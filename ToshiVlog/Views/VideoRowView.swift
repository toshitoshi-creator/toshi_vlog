import AVFoundation
import SwiftUI
import UIKit

struct VideoRowView: View {
    let video: VideoItem
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                Text(formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            thumbnail = await generateThumbnail()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: "video")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var formattedDuration: String {
        let totalSeconds = Int(video.duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func generateThumbnail() async -> UIImage? {
        let asset = AVURLAsset(url: video.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try await generator.image(at: .zero).image
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}
