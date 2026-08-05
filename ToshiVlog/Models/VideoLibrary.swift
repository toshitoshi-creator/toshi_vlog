import AVFoundation
import Observation

@MainActor
@Observable
final class VideoLibrary {
    private(set) var videos: [VideoItem] = []

    private var videosDirectory: URL {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func reload() async {
        let fileManager = FileManager.default
        let urls = (try? fileManager.contentsOfDirectory(
            at: videosDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )) ?? []

        var items: [VideoItem] = []
        for url in urls where url.pathExtension.lowercased() == "mov" {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let createdAt = (attributes?[.creationDate] as? Date) ?? Date()
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            items.append(VideoItem(
                id: UUID(),
                url: url,
                createdAt: createdAt,
                duration: duration.isFinite ? duration : 0
            ))
        }
        videos = items.sorted { $0.createdAt > $1.createdAt }
    }

    func store(temporaryURL: URL) async {
        let destination = videosDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            await reload()
        } catch {
            print("動画の保存に失敗しました: \(error)")
        }
    }

    func delete(_ item: VideoItem) async {
        try? FileManager.default.removeItem(at: item.url)
        await reload()
    }
}
