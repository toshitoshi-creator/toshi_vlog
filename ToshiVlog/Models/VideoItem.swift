import Foundation

struct VideoItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let createdAt: Date
    let duration: TimeInterval
}
