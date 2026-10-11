import Foundation
import Testing
@testable import Signet

/// S13: artwork URLs come from token metadata, so only public HTTPS destinations may be contacted
/// and an IPFS path may not climb out of the gateway's `/ipfs/`.
struct ArtworkPolicyTests {
    static let cid = "QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgnc"

    @Test(arguments: ["127.0.0.1", "10.1.2.3", "192.168.1.9", "169.254.169.254", "172.16.0.1", "172.31.255.255", "100.64.0.1", "0.0.0.0",
                      "::1", "::", "fc00::1", "fd12::3", "fe80::1", "::ffff:10.0.0.1", "[::1]", "localhost", "foo.local", "api.internal", "printer", "router.lan"])
    func classifiesPrivateHosts(host: String) {
        #expect(EndpointPolicy.isLocalOrPrivateHost(host))
    }

    @Test(arguments: ["8.8.8.8", "example.org", "ipfs.filebase.io", "2606:4700:4700::1111", "172.32.0.1", "11.0.0.1"])
    func classifiesPublicHosts(host: String) {
        #expect(!EndpointPolicy.isLocalOrPrivateHost(host))
    }

    @Test func checksSchemeCredentialsAndHost() throws {
        #expect(EndpointPolicy.check(try #require(URL(string: "https://example.org/a.png"))) == .allowed)
        #expect(EndpointPolicy.check(try #require(URL(string: "http://example.org/a.png"))) == .notHTTPS)
        #expect(EndpointPolicy.check(try #require(URL(string: "http://example.org/a.png")), allowHTTP: true) == .allowed)
        #expect(EndpointPolicy.check(try #require(URL(string: "https://user:pw@example.org/a.png"))) == .hasUserInfo)
        #expect(EndpointPolicy.check(try #require(URL(string: "https://127.0.0.1:8732/x"))) == .localOrPrivate("127.0.0.1"))
        #expect(EndpointPolicy.check(try #require(URL(string: "https://[::1]/x"))) == .localOrPrivate("::1"))
        #expect(EndpointPolicy.check(try #require(URL(string: "ftp://example.org/x"))) == .notHTTPS)
        #expect(!EndpointPolicy.isPublicHTTPS(try #require(URL(string: "https://localhost/x"))))
    }

    @Test(arguments: [
        "http://example.org/a.png",                        // not https
        "https://127.0.0.1/a.png",                          // loopback
        "https://[::1]:8080/a.png",                         // loopback v6
        "https://10.0.0.5/a.png",                           // private
        "https://192.168.0.1/a.png",                        // private
        "https://169.254.169.254/latest/meta-data",         // link local
        "https://localhost:8732/chains/main",               // local name
        "https://nas.local/a.png",                          // mDNS
        "https://user:secret@example.org/a.png",            // credentials
        "file:///etc/passwd",
        "data:image/png;base64,AAAA",
    ])
    func dropsUnsafeArtworkURLs(uri: String) {
        #expect(IPFS.candidateURLs(for: uri).isEmpty)
        #expect(IPFS.httpURL(for: uri) == nil)
    }

    @Test func keepsPublicHTTPSArtwork() {
        #expect(IPFS.candidateURLs(for: "https://example.org/a.png").map(\.absoluteString) == ["https://example.org/a.png"])
        #expect(IPFS.candidateURLs(for: "ipfs://\(Self.cid)").count == IPFS.gateways.count)
        #expect(IPFS.candidateURLs(for: "ipfs://\(Self.cid)/images/one.png").first?.absoluteString == "https://ipfs.filebase.io/ipfs/\(Self.cid)/images/one.png")
        // A gateway URL on a private host still yields our gateways, never the private one.
        let widened = IPFS.candidateURLs(for: "https://10.0.0.1/ipfs/\(Self.cid)")
        #expect(widened.count == IPFS.gateways.count)
        #expect(!widened.contains { $0.host() == "10.0.0.1" })
    }

    @Test(arguments: [
        "ipfs://\(cid)/../../etc/passwd",
        "ipfs://\(cid)/a/../b",
        "ipfs://\(cid)/%2e%2e/x",
        "ipfs://\(cid)//x",
        "ipfs://\(cid)/a%2Fb/../c",
        "ipfs://\(cid)/a\\..\\b",
        "ipfs://QmShort",
        "ipfs://not-a-cid/x",
        "ipfs://../../\(cid)",
        "https://gateway.pinata.cloud/ipfs/\(cid)/../other",
    ])
    func refusesTraversalAndBadCIDs(uri: String) {
        #expect(IPFS.candidateURLs(for: uri).isEmpty, "\(uri)")
    }

    @Test func encodesPathComponentsSoTheyStayUnderTheCID() throws {
        let urls = IPFS.candidateURLs(for: "ipfs://\(Self.cid)/a b/c;d.png?x=1")
        let first = try #require(urls.first)
        #expect(first.absoluteString == "https://ipfs.filebase.io/ipfs/\(Self.cid)/a%20b/c%3Bd.png?x=1")
        #expect(first.pathComponents.filter { $0 != "/" }.prefix(2) == ["ipfs", Self.cid])
        #expect(IPFS.path(of: "ipfs://\(Self.cid)/") == Self.cid + "/")
        #expect(IPFS.path(of: "ipfs://ipfs/\(Self.cid)") == Self.cid)
        #expect(IPFS.looksLikeCID(Self.cid))
        #expect(IPFS.looksLikeCID("bafybeigqka2ynrib6ytxku3nvakork5smsxni5xdqro56kd7ecsfos7z7a"))
        #expect(!IPFS.looksLikeCID("QmNrhZHUaEqxhyLfqoq1mtHSipkWHeT31LNHb1QEbDHgn0"))   // 0 is not base58
        #expect(!IPFS.looksLikeCID("bafy/../x"))
    }

    @Test func acceptsOnlyImageResponsesWithinTheByteLimit() {
        #expect(ImageLoader.acceptsResponse(status: 200, contentType: "image/png", contentLength: 1000))
        #expect(ImageLoader.acceptsResponse(status: 200, contentType: "image/svg+xml; charset=utf-8", contentLength: nil))
        #expect(ImageLoader.acceptsResponse(status: 200, contentType: nil, contentLength: nil))
        #expect(!ImageLoader.acceptsResponse(status: 200, contentType: "text/html", contentLength: 10))
        #expect(!ImageLoader.acceptsResponse(status: 200, contentType: "application/json", contentLength: 10))
        #expect(!ImageLoader.acceptsResponse(status: 302, contentType: "image/png", contentLength: 10))
        #expect(!ImageLoader.acceptsResponse(status: 429, contentType: "image/png", contentLength: 10))
        #expect(!ImageLoader.acceptsResponse(status: 200, contentType: "image/png", contentLength: Int64(ImageLoader.maxBytes) + 1))
        #expect(ImageLoader.downsample(Data(repeating: 0, count: ImageLoader.maxBytes + 1), maxPixelSize: 10) == nil)
    }
}
