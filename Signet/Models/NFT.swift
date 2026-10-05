import Foundation

/// A non-fungible token owned by the selected wallet. Only what the thumbnail grid needs.
struct NFT: Identifiable, Hashable, Sendable {
    /// `<contract>:<tokenId>`
    let id: String
    let contract: String
    let tokenId: String
    let name: String
    /// How many editions of this token the wallet holds (usually 1).
    let balance: Decimal
    /// HTTPS URLs to try for the tile image, best first (one per IPFS gateway).
    let imageURLs: [URL]

    var thumbnailURL: URL? { imageURLs.first }

    init(id: String, contract: String, tokenId: String, name: String, balance: Decimal, imageURLs: [URL]) {
        self.id = id
        self.contract = contract
        self.tokenId = tokenId
        self.name = name
        self.balance = balance
        self.imageURLs = imageURLs
    }

    init(id: String, contract: String, tokenId: String, name: String, balance: Decimal, thumbnailURL: URL?) {
        self.init(id: id, contract: contract, tokenId: tokenId, name: name, balance: balance, imageURLs: thumbnailURL.map { [$0] } ?? [])
    }
}
