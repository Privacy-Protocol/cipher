# Governance Fuzz & Invariant Test Plan

Fuzz-testing plan for the confidential governance stack, derived from the contract sources:

- [GovernorConfidential.sol](contracts/contracts/Governance/GovernorConfidential.sol)
- [GovernorCountingSimpleConfidential.sol](contracts/contracts/Governance/GovernorCountingSimpleConfidential.sol)
- [GovernorVotesConfidential.sol](contracts/contracts/Governance/GovernorVotesConfidential.sol)
- [GovernorVotesQuorumFractionConfidential.sol](contracts/contracts/Governance/GovernorVotesQuorumFractionConfidential.sol)
- [MyGovernor.sol](contracts/contracts/MyGovernor.sol)

Target harness: Foundry (`test-forge/`) with `forge-fhevm`, which exposes the FHE coprocessor mock so encrypted handles can be created and decrypted inside fuzz/invariant runs. Stateless tests use `forge` property fuzzing (random inputs per call). Stateful tests use a handler/actor model under `[invariant]` with `quorumReached`/`voteSucceeded`/`proposalVotes` decryption as the oracle.

---

## Part 1 — Invariants

These are the properties the fuzz campaign must never violate. Each is tagged with the contract it lives in.

### Tally & vote accounting (GovernorCountingSimpleConfidential)

- **I1 — Weight conservation.** For any proposal, `decrypt(forVotes) + decrypt(againstVotes) + decrypt(abstainVotes)` equals the sum of `getPastVotes(voter, snapshot)` over every voter whose `support ∈ {0,1,2}`. Votes with out-of-range support contribute **0** to all three counters (every `FHE.eq` is false, so every `FHE.select` picks the zero branch) — the weight is silently dropped. See [L86-L99](contracts/contracts/Governance/GovernorCountingSimpleConfidential.sol#L86-L99).
- **I2 — Single counter per vote.** A single vote increments exactly one counter by its full weight and the other two by zero; it can never split or double-count weight.
- **I3 — Monotonic counters.** `forVotes`, `againstVotes`, `abstainVotes` are non-decreasing across the life of a proposal (every increment is `≥ 0`).
- **I4 — One vote per account.** `hasVoted[proposalId][voter]` transitions `false → true` exactly once; a second cast reverts `GovernorAlreadyCastVote`. The count of `true` entries equals the number of successful casts. See [L78-L82](contracts/contracts/Governance/GovernorCountingSimpleConfidential.sol#L78-L82).
- **I5 — Snapshot-fixed weight.** A vote's contribution equals `getPastVotes(voter, proposalSnapshot)`; delegations/transfers after the snapshot do not change it. See [L207](contracts/contracts/Governance/GovernorConfidential.sol#L207).
- **I6 — Lazy init idempotence.** The `!FHE.isInitialized` branch runs at most once per proposal; counters start at encrypted 0 and the contract retains `allowThis` access after every mutation.

### Result lifecycle (GovernorConfidential)

- **I7 — Finalize implies requested.** `finalized == true ⇒ decryptionRequested == true`. The reverse can be false (requested but not yet finalized). No state path sets `finalized` without first setting `decryptionRequested`.
- **I8 — Write-once decryption request.** `requestProposalResultDecryption` succeeds at most once per proposal (`ResultAlreadyRequested` thereafter), and only strictly after `clock() > proposalDeadline`.
- **I9 — Write-once finalization.** `finalizeProposalResult` succeeds at most once per proposal (`ResultAlreadyFinalized` thereafter).
- **I10 — Result immutability.** Once `finalized`, `quorumReached(id)` and `voteSucceeded(id)` are constant for all subsequent calls and blocks.
- **I11 — Result correctness.** At finalization, `voteSucceeded == (decrypt(forVotes) > decrypt(againstVotes))` and `quorumReached == (decrypt(forVotes) + decrypt(abstainVotes) ≥ decrypt(confidentialQuorum(snapshot)))`. Ties (`for == against`) yield `voteSucceeded == false`.
- **I12 — No cleartext path.** `getVotes`, `castVote*` (non-encrypted), `_countVote`, and `_castVote` always revert; encrypted weight never leaks through a cleartext entry point.
- **I13 — Nonce monotonicity.** Each successful `*BySig` vote consumes exactly one nonce for `voter` (`nonces(voter)` increments by 1); a replay with the same nonce reverts `GovernorInvalidSignature`.

### Quorum fraction (GovernorVotesQuorumFractionConfidential)

- **I14 — Numerator bound.** `quorumNumerator() ≤ quorumDenominator() == 100` holds after every `updateQuorumNumerator`, for any sequence of updates.
- **I15 — Quorum formula.** `decrypt(confidentialQuorum(t)) == floor(getPastTotalSupply(t) · quorumNumerator(t) / 100)`, and is `≤ getPastTotalSupply(t)` (since numerator ≤ 100). Zero supply ⇒ encrypted 0.
- **I16 — Snapshot-fixed numerator.** A proposal evaluates quorum with the numerator at its snapshot, not the latest value. Updating the numerator after a proposal's snapshot does not change that proposal's quorum. See [L49](contracts/contracts/Governance/GovernorCountingSimpleConfidential.sol#L49) + [L28-L30](contracts/contracts/Governance/GovernorVotesQuorumFractionConfidential.sol#L28-L30).
- **I17 — Checkpoint ordering.** `_quorumNumeratorHistory` keys are strictly non-decreasing in `clock()`; `quorumNumerator(t)` returns the value in effect at `t` (latest for `t ≥ newest key`, historical otherwise).
- **I18 — Governance gate.** `updateQuorumNumerator` only mutates state when called via the governance executor; any other caller reverts `GovernorOnlyExecutor`.

### Clock (GovernorVotesConfidential)

- **I19 — Clock delegation/fallback.** `clock()` equals `token().clock()` when the token implements ERC-6372, else `Time.blockNumber()`; it is monotonically non-decreasing within a run. `CLOCK_MODE()` mirrors the same try/catch.

---

## Part 2 — Stateless fuzz tests

Single-call property tests over randomized inputs. No persisted actor sequence.

### GovernorVotesQuorumFractionConfidential

- **S1** `_updateQuorumNumerator(n)` — for fuzzed `n`: reverts `GovernorInvalidQuorumFraction` iff `n > 100`; otherwise `quorumNumerator() == n` afterward. Sweep boundaries `{0, 100, 101, type(uint256).max}`.
- **S2** `confidentialQuorum` math — fuzz `(totalSupply, numerator ∈ [0,100])`; assert `decrypt(confidentialQuorum) == totalSupply * numerator / 100` (Solidity floor div). Covers I15.
- **S3** `euint128 → euint64` narrowing — fuzz `totalSupply` near `2^64` with `numerator == 100`; assert either the decrypted quorum matches the true product (no truncation) or document the overflow boundary. Targets the `FHE.asEuint64(FHE.div(...))` narrowing at [L52](contracts/contracts/Governance/GovernorVotesQuorumFractionConfidential.sol#L52).
- **S4** `quorum(uint256)` — for any fuzzed timepoint, always reverts `GovernorConfidentialQuorumIsEncrypted`.
- **S5** `quorumDenominator()` — invariant constant `== 100` (trivial, anchors S1/S2).

### GovernorCountingSimpleConfidential

- **S6** Support routing — fuzz an encrypted `support` byte; cast a single vote with fixed weight `w`. Assert: `support==0 ⇒ against==w`; `==1 ⇒ for==w`; `==2 ⇒ abstain==w`; `support>2 ⇒ all three == 0` (weight dropped — I1 edge).
- **S7** Weight fidelity — fuzz `w`; single FOR vote ⇒ `decrypt(forVotes) == w`, the other two `== 0`.
- **S8** Tie/threshold success — fuzz `(for, against)`; `voteSucceeded == (for > against)` including the `for == against` tie ⇒ `false` (I11).
- **S9** Quorum threshold — fuzz `(forPlusAbstain, quorum)`; `quorumReached == (forPlusAbstain ≥ quorum)` (note `FHE.le` is inclusive — meeting the threshold exactly reaches quorum).

### GovernorConfidential

- **S10** Cleartext rejection — fuzz `(account, timepoint, support, reason, params)`; each of `getVotes`, `castVoteWithReason`, `castVoteWithReasonAndParams`, `castVoteBySig`, `castVoteWithReasonAndParamsBySig` reverts with the matching `NormalVotes/NormalGetVotes` error (I12).
- **S11** Signature validity — fuzz a signer key and voter address; `castEncryptedVoteBySig` succeeds iff the recovered signer matches `voter`, else reverts `GovernorInvalidSignature` (I13). Include a fuzzed wrong `supportProof` (hashed into the digest) to confirm proof tampering invalidates the signature.
- **S12** `params.length` branch — fuzz `params`; empty ⇒ `EncryptedVoteCast`, non-empty ⇒ `EncryptedVoteCastWithParams` (the event-selection branch at [L210-L214](contracts/contracts/Governance/GovernorConfidential.sol#L210-L214)).
- **S13** Lifecycle guards — fuzz a random `proposalId` never created; `requestProposalResultDecryption` reverts `GovernorNonexistentProposal`, `finalizeProposalResult` reverts `ResultDecryptionNotRequested`, `quorumReached`/`voteSucceeded` revert `ResultNotFinalized`.

---

## Part 3 — Stateful (invariant) fuzz tests

Handler-driven actor model. The handler exposes a bounded action set; Foundry sequences random calls across N actors, and invariants are asserted after each sequence. Decrypt the encrypted tallies/results in the invariant body as the oracle.

### Handler action surface

- `propose()` / advance clock past `votingDelay` into Active.
- `castEncryptedVote(actorSeed, supportSeed, proposalSeed)` — bounds `actor` to the registered set, `support` to a fuzzed byte (deliberately include `>2`).
- `delegate(fromSeed, toSeed)` — exercises I5/I16 (post-snapshot delegation must not move counted weight).
- `warp(timeSeed)` — moves `clock()` to drive Pending → Active → past-deadline transitions.
- `requestDecryption(proposalSeed)` / `finalize(proposalSeed)` — may be called at arbitrary (including illegal) times; reverts are caught and counted, not bubbled.
- `updateQuorumNumerator(nSeed)` — via the governance executor path.

### Invariants asserted after every call sequence

- **SF1 (I1, I2)** Sum of decrypted `for + against + abstain` for each proposal equals the handler's ghost sum of counted weights (ghost only accumulates weight for in-range support). Flags any leak/double-count.
- **SF2 (I4)** Handler ghost `votedCount[proposalId]` equals the number of `hasVoted == true` accounts; no account votes twice.
- **SF3 (I3)** Each counter is `≥` its value recorded after the previous sequence step (monotonic, never decreases).
- **SF4 (I5, I16)** For every finalized proposal, recomputing the expected result from snapshot-time weights and snapshot-time numerator equals the on-chain finalized `(quorumReached, voteSucceeded)` — even when delegations and `updateQuorumNumerator` happened after the snapshot.
- **SF5 (I7, I8, I9, I10)** Result state machine: never `finalized && !decryptionRequested`; `requestDecryption` and `finalize` each succeed at most once per proposal; a finalized proposal's `(quorumReached, voteSucceeded)` are byte-identical across all later reads.
- **SF6 (I14, I17)** After any `updateQuorumNumerator` sequence, `quorumNumerator() ≤ 100`, and `_quorumNumeratorHistory` checkpoint keys are non-decreasing; `quorumNumerator(t)` for a sampled past `t` returns the value that was latest at `t`.
- **SF7 (I13)** Across all `*BySig` actions, `nonces(voter)` equals the handler's count of that voter's successful sig-votes; no replay succeeds.
- **SF8 (I19)** `clock()` observed across the sequence is non-decreasing.
- **SF9 (state legality)** A vote only ever succeeds while the proposal is `Active`; casts attempted in `Pending` or past-deadline are reverts (caught), never silent successes. Note the past-deadline cast reverts `ResultNotFinalized` (not `UnexpectedProposalState`) because `state()` evaluates `_quorumReached` internally — see [L114-L116](contracts/contracts/Governance/GovernorConfidential.sol#L114-L116) and the base `_validateStateBitmap` path.

### Suggested ghost variables

- `mapping(uint256 => uint256) ghostCountedWeight` — per-proposal sum of in-range vote weights.
- `mapping(uint256 => uint256) ghostVotedCount`.
- `mapping(address => uint256) ghostSigVotes`.
- `mapping(uint256 => bool) ghostRequested / ghostFinalized` and a snapshot of finalized `(bool,bool)` for immutability checks.
- `uint48 lastClock` for monotonicity.

### Known sharp edges to seed into the corpus

1. **Out-of-range support** (`support ≥ 3`) — weight is dropped (I1); ensure SF1's ghost mirrors this rather than assuming all weight lands.
2. **Numerator update mid-proposal** — must not retro-change an already-snapshotted proposal's quorum (SF4).
3. **`euint64` tally overflow** — many large-weight votes can overflow the 64-bit counter; decide whether this is in-scope and assert the wrap boundary explicitly (S3-adjacent).
4. **Exact-threshold quorum** — `FHE.le` is inclusive; `forPlusAbstain == quorum` reaches quorum (S9).
5. **Exact tie** — `FHE.gt` is strict; `for == against` fails (S8).
