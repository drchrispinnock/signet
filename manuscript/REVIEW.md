# Book review - consistency 15/11/2026

Tidied and rechecked against the chapters on disk on 21 November 2026. Line numbers are as of that check. Items that are now fixed are under DONE at the end.

{id: REVIEW_2_Consistenc}

## Consistency and presentation pass

### Placeholders (resolve before publishing)

### Style and wording

### Layout

## Claims still requiring author or release-specific verification

These are scoped checks, not claims that the text is wrong. The author's own experience and decisions stand.

- [x] **Transaction retry:** [140-transactions.md:56](140-transactions.md#L56) now says to wait and check before trying again. Consider naming the operation hash/status explicitly as what to check, since a timeout doesn't prove the transaction failed. This is nearly resolved.
- [x] **Double signing precision:** "double-sign a block at the same level" at [160-delegatingstaking.md:106](160-delegatingstaking.md#L106) (also line 46) should use level and round. Qualify the remote-signer protection at line 108 and [190-baking.md:167](190-baking.md#L167) as depending on the signer's enabled, persistent high-watermark state, and tie stake loss to the offence and the protocol.
- [x] **Chain-ID mismatch behaviour:** [165-settings.md:45](165-settings.md#L45) says Signet "will warn us". Check against the released app whether the user can carry on after the warning, and say so.
- [x] **Date-sensitive market claims:** Objkt's "over 7 million pieces" at [170-dapps.md:47](170-dapps.md#L47), baker APYs and capacity at [160-delegatingstaking.md:33](160-delegatingstaking.md#L33), and the roadmap in chapter 250. Date them where useful.
- [x] **NFT rights (optional):** add a sentence near [170-dapps.md:101](170-dapps.md#L101) separating ownership of the token from rights to the artwork.
- [x] **Consensus and companion key roles:** [190-baking.md:6](190-baking.md#L6) says the consensus key "signs blocks" but doesn't mention ordinary consensus attestations. Check both keys' roles against the protocol being demonstrated.
