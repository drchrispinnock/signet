import SwiftUI

/// Grid of NFT thumbnails at the bottom of the default screen.
struct NFTGridView: View {
    let nfts: [NFT]
    let isLoading: Bool

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NFTs")
                    .font(.headline)
                if !nfts.isEmpty {
                    Text("\(nfts.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))
                }
                Spacer()
            }

            if nfts.isEmpty {
                Text(isLoading ? "Loading…" : "No NFTs in this wallet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(nfts) { nft in
                            NFTTileView(nft: nft)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(minHeight: 180, idealHeight: 300)
    }
}

struct NFTTileView: View {
    let nft: NFT

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A square frame that the image fills and is centre-cropped to.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay { thumbnail }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.25)))
                .overlay(alignment: .topTrailing) {
                    if nft.balance > 1 {
                        Text("×\(nft.balance)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
            Text(nft.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
        .help("\(nft.name)\n\(nft.contract) #\(nft.tokenId)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(nft.name)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if nft.imageURLs.isEmpty {
            placeholder(systemImage: "photo")
        } else {
            RemoteImage(urls: nft.imageURLs) { image in
                Image(nsImage: image).resizable().scaledToFill()
            } placeholder: { failed in
                placeholder(systemImage: failed ? "photo.badge.exclamationmark" : nil)
            }
        }
    }

    private func placeholder(systemImage: String?) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

#Preview {
    NFTGridView(nfts: (1...5).map { NFT(id: "k:\($0)", contract: "KT1x", tokenId: "\($0)", name: "NFT number \($0)", balance: $0 == 2 ? 20 : 1, thumbnailURL: nil) }, isLoading: false)
        .padding()
}

/// Loads an image through `ImageLoader`, trying each URL in turn.
struct RemoteImage<Content: View, Placeholder: View>: View {
    let urls: [URL]
    @ViewBuilder let content: (NSImage) -> Content
    @ViewBuilder let placeholder: (_ failed: Bool) -> Placeholder

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder(failed)
            }
        }
        .task(id: urls) {
            failed = false
            image = await ImageLoader.shared.image(for: urls)
            if image == nil { failed = true }
        }
    }
}
