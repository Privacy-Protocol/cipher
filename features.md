# Cipher — Feature Tracker

Running log of the privacy primitives Cipher adapters expose. Cipher's goal is to let
developers drop confidentiality + ZK into existing apps (contract / frontend / backend) without
rolling their own cryptography. The first adapter is the **DAO adapter**.

---

## DAO Adapter — `PrivateDaoAdapter`

`contracts/contracts/DaoToolkit/PrivateDaoAdapter.sol` — a confidential, OpenZeppelin-style
Governor with an **optional** zero-knowledge membership gate. Concrete demo deployment:
`contracts/contracts/demo/DaoToolkit/DemoDao.sol`.

Design principle: **privacy by default, ZK by choice.** Every DAO built on the adapter is
confidential out of the box (FHE-encrypted ballots + tally). The ZK membership gate is a layer a
team can switch on when they need anonymous, sybil-resistant eligibility — and switch off when
they don't.

### Core features (confidential by default)

| Feature | Where | Notes |
| --- | --- | --- |
| FHE-encrypted ballots | `Governance/GovernorConfidential.sol` | Votes are `externalEuint8` handles; cleartext choice never hits the chain |
| Homomorphic tally | `Governance/GovernorCountingSimpleConfidential.sol` | Against/For/Abstain kept as `euint64`, summed under FHE |
| Token-weighted voting power | `Governance/GovernorVotesConfidential.sol` + `Tokens/ERC7984.sol` | Weight from a confidential ERC-7984 votes token; delegation required before snapshot |
| Encrypted quorum | `Governance/GovernorVotesQuorumFractionConfidential.sol` | Quorum (4%) compared against encrypted total supply |
| Two-phase result decryption | `GovernorConfidential.sol` | `requestProposalResultDecryption` → Zama KMS `publicDecrypt` → `finalizeProposalResult`; only the two result booleans are ever revealed, individual ballots + tallies stay encrypted forever |
| Standard Governor lifecycle | inherited from OZ `Governor` | `propose` / `state` / `execute`, timestamp clock, 2h delay / 14h period |

A DAO that wants confidentiality only (no ZK) is fully supported — see `MyGovernor.sol`, or deploy
the adapter with the gate disabled (below).

### ZK membership gate (optional)

| Feature | Where | Notes |
| --- | --- | --- |
| Noir membership proof | `circuits/` + `DaoToolkit/VoteSubmissionVerifier.sol` (Honk verifier) | Proves the caller's identity secret is a leaf in a Poseidon2 merkle tree (depth 32) without revealing which one |
| One-time nullifier | `PrivateDaoAdapter._verifyMembership` | `nullifier = Poseidon2(proposalId mod BN254, secret)`; spent nullifiers tracked per proposal to block double-voting across wallets |
| Gated vote entrypoint | `castEncryptedVoteWithMembershipProof(...)` | The only valid vote path while the gate is on; carries the FHE ballot + Noir proof + nullifier in one tx |
| Membership root rotation | `setMembershipRoot(bytes32)` (owner) | Update the member set without redeploying; only while the gate is enabled |

### Flexible privacy primitive — the headline feature

The ZK gate is **not mandatory** and is **not fixed at deploy time**.

| Capability | API | Behavior |
| --- | --- | --- |
| Deploy ZK-disabled (FHE-only) | `constructor(token, address(0), bytes32(0))` | Behaves like a plain confidential DAO; members vote with the inherited `castEncryptedVote*` entrypoints |
| Deploy ZK-enabled | `constructor(token, verifier, root)` | Un-gated entrypoints disabled; voting must go through `castEncryptedVoteWithMembershipProof` |
| **Switch ZK on/off later** | `setZkMembership(verifier, root)` (owner) | Enable, disable, or reconfigure the gate at runtime — verifier is mutable storage, not immutable |
| Introspect the mode | `zkMembershipEnabled() → bool` | Frontends/backends branch on this to pick the vote path |

Validation is shared between the constructor and `setZkMembership` (`_configureZkMembership`):
a non-zero verifier (with code) + non-zero canonical root **enables**; a zero verifier + zero
root **disables**; any other combination reverts. Conditional entrypoints: the inherited
`castEncryptedVote*` functions pass through to the confidential governor when the gate is off and
revert `PDA__MembershipProofRequired` when it is on.

> ⚠️ Toggling changes which vote path is valid. Reconfigure the gate **between proposals**, not
> during an active voting window. Enforced only by convention (documented in NatSpec), not on-chain.

### Events

- `PDA__ZkMembershipConfigured(verifier, membershipRoot, enabled)` — emitted by the constructor and every `setZkMembership` call
- `PDA__MembershipRootUpdated(previousRoot, newRoot)` — `setMembershipRoot`
- `PDA__MembershipVoteCast(proposalId, nullifierHash)` — a gated vote was accepted
- `EncryptedVoteCast` / `ProposalResultDecryptionRequested` / `ProposalResultFinalized` — from `GovernorConfidential`

### Errors

`PDA__InvalidVerifier`, `PDA__InvalidMembershipRoot`, `PDA__FieldElementOutOfRange`,
`PDA__NullifierAlreadyUsed`, `PDA__InvalidMembershipProof`, `PDA__MembershipProofRequired`
(gate on, wrong entrypoint), `PDA__MembershipProofNotEnabled` (gate off, ZK-only call).

### Test coverage

`contracts/test/DemoDao.ts` — full membership-gated flow, nullifier reuse rejection, wrong-proposal
proof rejection; FHE-only mode (gate disabled) voting + entrypoint guards; runtime enable→prove,
runtime disable→un-gated vote, `setZkMembership` owner-gating + argument validation. Plus
`MyGovernor.ts` for the standalone confidential governor. (65 tests passing.)

---

## Changelog

- **Optional ZK gate** — adapter no longer forces ZK; deploy with `(address(0), bytes32(0))` for a
  confidential-only DAO. Inherited `castEncryptedVote*` entrypoints conditionally re-enabled.
- **Runtime toggling** — `setZkMembership(verifier, root)` + mutable verifier + `zkMembershipEnabled()`
  view + `PDA__ZkMembershipConfigured` event; the gate can be enabled/disabled/reconfigured after
  deployment by the owner.

## Frontend integration (reference dapp)

The `frontend tester/privacy-protocol-tester` app demonstrates a complete integration and closes
the member loop end-to-end in the browser (see its `INTEGRATION.md`):

- **Mode-aware voting** — reads `zkMembershipEnabled()` and uses the membership-proof path when on,
  plain `castEncryptedVote` when off.
- **Operator tooling** — build the Poseidon2 root from identity secrets **or** leaf commitments,
  export the public member set, and (secrets mode) export per-member proving kits; runtime
  enable/disable via `setZkMembership`.
- **Member lifecycle** (`/membership`) — generate a private identity (secret + leaf commitment),
  build a proving kit from the published member set (sibling path derived locally, secret never
  leaves the device), or import an operator-provisioned kit; kits persist per chain+DAO.
- **Kit-based proving** — a member votes from their own kit alone (`generateMembershipProofFromKit`),
  needing no other member's data.

Client-side stack: `@noir-lang/noir_js` + `@aztec/bb.js` (Poseidon2 + UltraHonk, `keccakZK`) and
`@zama-fhe/relayer-sdk` (FHE input encryption + KMS decryption).

## Roadmap / ideas (not built)

- On-chain guard to block gate toggling while a proposal is active.
- Additional Cipher adapters beyond DAO governance.
- SDK helpers (`sdk/`) wrapping proof generation + FHE input encryption for backend integrations.
