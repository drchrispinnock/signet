// Etherlink's on-chain governance (kernel upgrades) lives in layer 1 contracts written by
// Baking Bad (github.com/baking-bad/etherlink-governance): `new_proposal` and
// `upvote_proposal` take a 33-byte kernel root hash in a Proposal period, `vote` takes
// "yea", "nay" or "pass" in the Promotion period that follows, and every call is an ordinary
// transaction with a fee, so it goes through the approved-limits path (S14, S15).
//
// Reading the state: the contract computes the period from the level, `started_at_level` and
// `period_length` (its `get_voting_state` view does the same, but public nodes such as
// rpc.tzbeta.net refuse `run_script_view`, so it is computed here from the head level), while
// the storage's `voting_context` only moves when someone calls an entrypoint, so it may
// describe an earlier period. The rule from the contract source (voting.mligo): a stored
// context for the same period index is current; a Promotion whose stored context is the
// previous Proposal period takes that period's winner as its candidate with nothing voted
// yet; any other stored context belongs to a finished period and the current one is empty.
// Voting keys are read from the delegation contract's `voting_delegations` big map, which is
// what its `list_voters` view answers from.

import { TezosToolkit, MichelCodecPacker } from "@taquito/taquito";
import { signerFor, readOnlySigner } from "./signers.js";
import { approvedEstimate, sendApproved, parseLimits } from "./operations.js";

const KT1 = /^KT1[1-9A-HJ-NP-Za-km-z]{33}$/;
const KERNEL_HASH = /^[0-9a-f]{66}$/;
const VOTES = ["yea", "nay", "pass"];

/** The transaction parameters for one governance call; checked before any signer or node is touched. */
export function governanceParams(contract, entrypoint, payload) {
  if (!KT1.test(contract)) throw new Error(`Not a governance contract: ${contract}`);
  let value;
  switch (entrypoint) {
    case "new_proposal":
    case "upvote_proposal": {
      const hex = String(payload ?? "").replace(/^0x/i, "").toLowerCase();
      if (!KERNEL_HASH.test(hex)) throw new Error("A kernel hash is 33 bytes: 0x followed by 66 hexadecimal digits");
      value = { bytes: hex };
      break;
    }
    case "vote":
      if (!VOTES.includes(payload)) throw new Error(`A vote is one of ${VOTES.join(", ")}`);
      value = { string: payload };
      break;
    default:
      throw new Error(`Unknown governance entrypoint ${entrypoint}`);
  }
  return { to: contract, amount: 0, mutez: true, parameter: { entrypoint, value } };
}

/** Fee and limits for `source` calling `entrypoint` on `contract`. */
export async function estimateEtherlinkGovernance(rpcUrl, source, publicKey, contract, entrypoint, payload) {
  const params = governanceParams(contract, entrypoint, payload);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(readOnlySigner(publicKey, source));
  return approvedEstimate(tk, "transaction", params, await tk.estimate.transfer(params));
}

/** Signs and injects the call with exactly the approved limits (S14); `{ hash, injected, signedBytes }` (S15). */
export async function sendEtherlinkGovernance(rpcUrl, signerSpec, contract, entrypoint, payload, limitsJson) {
  const params = governanceParams(contract, entrypoint, payload);
  const tk = new TezosToolkit(rpcUrl);
  tk.setSignerProvider(await signerFor(signerSpec));
  return sendApproved(tk, rpcUrl, "transaction", params, parseLimits(limitsJson));
}

// ---- Reading --------------------------------------------------------------------------------

async function getJSON(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url} answered ${r.status}`);
  return r.json();
}

/**
 * A toolkit for reading: big-map keys are packed locally (`MichelCodecPacker`) rather than by
 * the node's `pack_data` helper, which public nodes such as rpc.tzbeta.net refuse.
 */
function reader(rpcUrl) {
  const tk = new TezosToolkit(rpcUrl);
  tk.setPackerProvider(new MichelCodecPacker());
  return tk;
}

/** Taquito decodes an option of a record as `{ Some: value }` and None as null; plain options come through bare. */
const unwrapSome = (v) => (v && typeof v === "object" && "Some" in v && Object.keys(v).length === 1 ? v.Some : v);

const str = (v) => (v == null ? null : String(v));
const nat = (v) => {
  const s = str(v);
  if (s == null || !/^\d+$/.test(s)) throw new Error(`expected a natural number, got ${s}`);
  return s;
};
const small = (v) => {
  const n = Number(nat(v));
  if (!Number.isSafeInteger(n)) throw new Error(`number out of range: ${v}`);
  return n;
};
const sum = (values) => values.reduce((a, b) => a + BigInt(b), 0n).toString();

/**
 * The period index and blocks left at `level`, as the contract's `get_period_index` and
 * `get_current_period_remaining_blocks` compute them from `config` (voting.mligo). `level` is
 * the one an operation sent now would land in (the head's successor).
 */
export function periodAt(config, level) {
  const started = small(config?.started_at_level);
  const length = small(config?.period_length);
  const at = small(level);
  if (length <= 0) throw new Error("the governance contract has no period length");
  if (at < started) throw new Error("the governance contract has not started yet");
  const elapsed = at - started;
  return { index: Math.floor(elapsed / length), remaining: length - (elapsed % length) };
}

/**
 * The bakers one `voting_delegations` entry (baker → (granted, contracts option), as Taquito
 * decodes it) gives voting rights on `contract` to: granted, and for every contract or one
 * whose set names this one. This is what the delegation contract's `list_voters` answers.
 */
export function votersFrom(entry, contract) {
  if (entry == null) return [];
  const pairs = typeof entry.entries === "function" ? [...entry.entries()] : Object.entries(entry);
  const bakers = [];
  for (const [baker, raw] of pairs) {
    const value = unwrapSome(raw);
    const granted = value?.[0] ?? value?.bool ?? value?.granted;
    const scope = unwrapSome(value?.[1] ?? value?.set ?? value?.contracts ?? null);
    if (granted !== true) continue;
    if (scope != null && !(Array.isArray(scope) ? scope : [...scope]).map(String).includes(contract)) continue;
    bakers.push(String(baker));
  }
  return bakers.sort();
}

/** The delegation contract named in a governance contract's storage, remembered per contract. */
const delegationContracts = new Map();

async function storageOf(tk, contract) {
  const c = await tk.contract.at(contract);
  const storage = await c.storage();
  const delegation = str(storage?.config?.delegation_contract);
  if (delegation && KT1.test(delegation)) delegationContracts.set(contract, delegation);
  return storage;
}

async function votingRightsOf(tk, delegation, contract, address) {
  const c = await tk.contract.at(delegation);
  const storage = await c.storage();
  const delegations = storage?.voting_delegations;
  if (!delegations || typeof delegations.get !== "function") throw new Error(`${delegation} is not a voting-key contract`);
  return votersFrom(await delegations.get(address), contract);
}

/**
 * The bakers `address` is the Etherlink voting key of on `contract` (what the delegation
 * contract's `list_voters(address, Some contract)` answers, read from its big map), or []
 * when the governance contract names no delegation contract.
 */
export async function etherlinkVotingRights(rpcUrl, contract, address) {
  if (!KT1.test(contract)) throw new Error(`Not a governance contract: ${contract}`);
  const tk = reader(rpcUrl);
  if (!delegationContracts.has(contract)) await storageOf(tk, contract);
  const delegation = delegationContracts.get(contract);
  if (!delegation) return [];
  return votingRightsOf(tk, delegation, contract, address);
}

/**
 * Pure derivation of the current period's content: the computed period (`{ index, kind,
 * remaining }`), the storage's `voting_context` (as Taquito decodes it, or null) and the
 * chain's total voting power now (for a period nobody has touched yet). Big maps are left to
 * the caller; this decides which, if any, describe the current period.
 */
export function deriveState(view, context, totalVotingPowerNow) {
  const votingContext = unwrapSome(context);
  const stored = votingContext ? small(votingContext.period_index) : null;
  const period = votingContext?.period ?? {};
  const proposal = period.proposal ?? null;
  const promotion = period.promotion ?? null;
  const out = { periodIndex: view.index, periodKind: view.kind, remainingBlocks: view.remaining, totalVotingPower: nat(totalVotingPowerNow),
    current: null, candidate: null, tallies: { yea: "0", nay: "0", pass: "0" } };
  if (view.kind === "proposal") {
    if (stored === view.index && proposal) {
      out.current = "proposal";
      out.totalVotingPower = nat(proposal.total_voting_power);
    }
  } else if (stored === view.index && promotion) {
    out.current = "promotion";
    out.totalVotingPower = nat(promotion.total_voting_power);
    out.candidate = "0x" + str(unwrapSome(promotion.winner_candidate));
    out.tallies = { yea: nat(promotion.yea_voting_power), nay: nat(promotion.nay_voting_power), pass: nat(promotion.pass_voting_power) };
  } else if (stored === view.index - 1 && proposal && unwrapSome(proposal.winner_candidate) != null) {
    // The proposal period ended with a winner and nobody has called the contract since.
    out.candidate = "0x" + str(unwrapSome(proposal.winner_candidate));
  } else {
    throw new Error("The governance contract's storage does not match its voting state; try again in a moment");
  }
  return out;
}

/** TzKT's listing of a big map's active keys, as `[{ key, value }]`; null without an indexer. */
async function bigMapKeys(tzktUrl, ptr) {
  if (!tzktUrl) return null;
  const rows = await getJSON(`${tzktUrl.replace(/\/+$/, "")}/v1/bigmaps/${ptr}/keys?active=true&limit=1000`);
  if (!Array.isArray(rows)) throw new Error("unexpected big map listing");
  return rows;
}

/**
 * The current period of `contract` and where `address` stands in it. `tzktUrl` (may be empty)
 * lists the proposals; without it only our own entries can be looked up.
 */
export async function getEtherlinkGovernanceState(rpcUrl, contract, address, tzktUrl) {
  if (!KT1.test(contract)) throw new Error(`Not a governance contract: ${contract}`);
  const base = rpcUrl.replace(/\/+$/, "");
  const tk = reader(rpcUrl);
  const [header, totalNow, storage] = await Promise.all([
    getJSON(`${base}/chains/main/blocks/head/header`),
    getJSON(`${base}/chains/main/blocks/head/votes/total_voting_power`),
    storageOf(tk, contract),
  ]);
  const config = storage.config ?? {};
  // The period an operation sent now would land in: the head's successor, which is also what
  // the contract sees when it runs.
  const period = periodAt(config, small(header?.level) + 1);
  const votingContext = unwrapSome(storage.voting_context);
  const stored = votingContext ? small(votingContext.period_index) : null;
  // Which kind the current period is follows the contract's own transition (voting.mligo
  // init_new_voting_state): a stored context for this index says so; a Proposal period that
  // ended with a quorate winner is followed by one Promotion period; everything else is a
  // Proposal period.
  let kind = "proposal";
  if (stored === period.index) {
    kind = votingContext.period?.promotion ? "promotion" : "proposal";
  } else if (stored === period.index - 1 && votingContext.period?.proposal) {
    const p = votingContext.period.proposal;
    const best = unwrapSome(p.max_upvotes_voting_power);
    const quorate = best != null && BigInt(nat(best)) * BigInt(small(config.scale)) >= BigInt(nat(p.total_voting_power)) * BigInt(small(config.proposal_quorum));
    if (unwrapSome(p.winner_candidate) != null && quorate) kind = "promotion";
  }
  const derived = deriveState({ index: period.index, kind, remaining: period.remaining }, votingContext ?? null, totalNow);
  const out = {
    ...derived,
    config: { periodLength: small(config.period_length), upvotingLimit: small(config.upvoting_limit), scale: small(config.scale),
      proposalQuorum: small(config.proposal_quorum), promotionQuorum: small(config.promotion_quorum), promotionSupermajority: small(config.promotion_supermajority) },
    proposals: [], proposalsKnown: true, votingPower: "0", votesFor: [], upvotesUsed: 0, myVote: null,
  };

  // Our power: our own listing plus the bakers we are the voting key of (what the contract sums).
  const delegation = delegationContracts.get(contract);
  if (delegation) out.votesFor = await votingRightsOf(tk, delegation, contract, address);
  const listings = await getJSON(`${base}/chains/main/blocks/head/votes/listings`);
  const power = new Map(Array.isArray(listings) ? listings.map((l) => [l.pkh, nat(l.voting_power)]) : []);
  const voters = [address, ...out.votesFor.filter((b) => b !== address)];
  out.votingPower = sum(voters.map((v) => power.get(v) ?? "0"));

  const context = votingContext?.period ?? {};
  if (derived.current === "proposal") {
    const p = context.proposal;
    out.upvotesUsed = small((await p.upvoters_upvotes_count.get(address)) ?? 0);
    const rows = await bigMapKeys(tzktUrl, p.proposals.toString());
    if (rows) {
      out.proposals = rows.map((row) => ({
        hash: "0x" + String(row.key).toLowerCase(),
        proposers: Array.isArray(row.value?.proposers) ? row.value.proposers : [],
        upvotes: nat(row.value?.upvotes_voting_power),
        upvoted: false,
      }));
      out.proposals.sort((a, b) => (BigInt(b.upvotes) > BigInt(a.upvotes) ? 1 : BigInt(b.upvotes) < BigInt(a.upvotes) ? -1 : a.hash.localeCompare(b.hash)));
      for (const proposal of out.proposals) {
        proposal.upvoted = (await p.upvoters_proposals.get({ 0: address, 1: proposal.hash.slice(2) })) != null;
      }
    } else {
      out.proposalsKnown = false;
    }
  } else if (derived.current === "promotion") {
    const vote = await context.promotion.voters.get(address);
    out.myVote = VOTES.includes(vote) ? vote : null;
  }
  return out;
}
