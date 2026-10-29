
# Staked off-balance

I can't enforce that restriction myself: who can export or share this Project is set by your claude.ai organisation and sharing settings, not by anything I do. You'll want to lock it down there.

**On the staking question:** the two cases are accounted for differently, which is why the baker sees an exact 6000 ꜩ and an external staker may not.

**Baker's own stake.** The baker's frozen deposits are booked directly against the baker's account. Stake 6000 ꜩ and 6000 ꜩ moves into frozen deposits, with nothing in between.

**External stakers.** Their stake goes into a shared pool per baker, tracked with pseudotokens. When you stake, your tez are converted into pseudotokens at the pool's current ratio (stakers' frozen tez ÷ total pseudotokens). Your "staked balance" is then calculated back the other way, as your pseudotokens × the current ratio, rounded down. That design lets rewards and slashing hit the whole pool proportionally without updating every staker's account.

**What that explains, and what it doesn't.** Rounding in that round trip should cost you at most a mutez or so, not 0.01 ꜩ. A full 1% gap suggests something else is going on. The candidates I'd check:

- **Fees on the stake operation.** If you're comparing your total balance before and after, rather than the staked balance specifically, the fee comes off spendable.
- **Slashing being applied to the pool.** If the baker had a pending denunciation, it is applied to the stakers' pool. That reduces the tez backing every pseudotoken, including ones minted just before the slash landed.
- **Wallet display.** Some wallets show a derived or estimated figure rather than the RPC's `staked_balance`.

**How to pin it down:**

1. Query `/chains/main/blocks/head/context/contracts/<your_tz>/staked_balance` directly.
2. Look at the balance updates in the stake operation receipt. These show exactly what moved to deposits and what went to fees.
3. Check whether the baker had any denunciations around that cycle.

If you send me the operation hash and the network, I can help you trace where the 0.01 ꜩ went.
