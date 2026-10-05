import SwiftUI

/// Horizontal strip of NFT thumbnails at the bottom of the default screen.
struct NFTGridView: View {
    let nfts: [NFT]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(nfts) { nft in
                    NFTThumbnailView(nft: nft)
                }
            }
        }
        .frame(height: 96)
    }
}

struct NFTThumbnailView: View {
    let nft: NFT

    var body: some View {
        Group {
            if let url = nft.thumbnailURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.4)))
        .help(nft.name)
        .accessibilityLabel(nft.name)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Text("NFT")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NFTGridView(nfts: (1...4).map { NFT(id: "\($0)", name: "NFT \($0)", thumbnailURL: nil) })
        .padding()
}
