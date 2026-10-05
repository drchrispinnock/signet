import Foundation
import Testing
@testable import Signet

/// Live lookups against api.tezos.domains.
struct TezosDomainsTests {
    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func resolvesCaptainStake() async throws {
        let service = TezosDomainsService(endpoint: Network.mainnet.tezosDomainsURL!)
        let name = try await service.reverseName(for: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"))
        #expect(name == "captstake.tez")
    }

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func addressWithoutReverseRecordHasNoName() async throws {
        let service = TezosDomainsService(endpoint: Network.mainnet.tezosDomainsURL!)
        let name = try await service.reverseName(for: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"))
        #expect(name == nil)
    }

    @Test(.tags(.network), .timeLimit(.minutes(1)))
    func chainServiceReturnsZeroOrOneName() async throws {
        let service = TaquitoChainService(network: .mainnet)
        #expect(try await service.domains(for: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")) == ["captstake.tez"])
        #expect(try await service.domains(for: Address("tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")) == [])
    }

    @Test func networksWithoutDomainsReturnNothing() async throws {
        let service = TaquitoChainService(network: .shadownet)
        #expect(try await service.domains(for: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N")) == [])
    }
}
