import Foundation

/// A non-fungible token owned by the active account. Only what the thumbnail grid needs.
struct NFT: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let thumbnailURL: URL?
}
