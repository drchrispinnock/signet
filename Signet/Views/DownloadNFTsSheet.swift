import AppKit
import SwiftUI

/// Saves the artwork of one or many NFTs into the wallet directory's `nfts` folder, a row per
/// token with its progress, and shows the folder in the Finder when asked. Closing the sheet
/// stops whatever is still downloading; what was saved stays.
struct DownloadNFTsSheet: View {
    let downloader: NFTDownloader
    let download: NFTDownload

    @Environment(\.dismiss) private var dismiss
    @State private var outcomes: [NFT.ID: Outcome] = [:]

    enum Outcome: Equatable {
        case saved(URL)
        case failed(String)
    }

    private var finished: Bool { outcomes.count == download.nfts.count }
    private var saved: [URL] { download.nfts.compactMap { if case .saved(let url) = outcomes[$0.id] { url } else { nil } } }
    private var title: String { download.nfts.count == 1 ? "Download NFT" : "Download \(download.nfts.count) NFTs" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.weight(.semibold))
            Text("The full artwork of each token is saved into **\(downloader.directory.path)**, named after the token, its contract and its id.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(download.nfts) { nft in row(nft) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60, maxHeight: 280)
            summary
            HStack {
                Button("Show in Finder") { reveal() }.disabled(saved.isEmpty)
                Spacer()
                if finished {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .task { await run() }
    }

    private func row(_ nft: NFT) -> some View {
        HStack(spacing: 10) {
            Group {
                switch outcomes[nft.id] {
                case .saved: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                case nil: ProgressView().controlSize(.small)
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(nft.name).lineLimit(1).truncationMode(.tail)
                switch outcomes[nft.id] {
                case .saved(let url): Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                case .failed(let reason): Text(reason).font(.caption).foregroundStyle(.red)
                case nil: Text(nft.isMoving ? "Downloading the video or sound…" : "Downloading…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var summary: some View {
        if finished {
            let failed = download.nfts.count - saved.count
            if failed == 0 {
                Label(saved.count == 1 ? "Saved" : "Saved \(saved.count) files", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                Label("Saved \(saved.count) of \(download.nfts.count)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }

    /// Three at a time: the public client has six slots and the tiles may be loading too.
    private func run() async {
        await withTaskGroup(of: (NFT.ID, Outcome).self) { group in
            var pending = download.nfts[...]
            var running = 0
            func start(_ nft: NFT) {
                group.addTask {
                    do { return (nft.id, .saved(try await downloader.download(nft))) }
                    catch is CancellationError { return (nft.id, .failed("Cancelled")) }
                    catch { return (nft.id, .failed(error.localizedDescription)) }
                }
            }
            while running < 3, let next = pending.popFirst() { start(next); running += 1 }
            for await (id, outcome) in group {
                if !Task.isCancelled { outcomes[id] = outcome }
                if let next = pending.popFirst() { start(next) }
            }
        }
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(saved)
    }
}

#Preview {
    DownloadNFTsSheet(downloader: NFTDownloader(directory: URL(fileURLWithPath: "/tmp/nfts"), fetch: { _ in throw URLError(.cannotLoadFromNetwork) }),
                      download: NFTDownload(nfts: [NFT(id: "k:1", contract: "KT1RJ6PbjHpwc3M5rw5s2Nbmefwbuwbdxton", tokenId: "1", name: "Preview", balance: 1, thumbnailURL: URL(string: "https://ipfs.io/ipfs/x"))]))
}
