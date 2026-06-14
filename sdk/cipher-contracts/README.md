# Cipher Contracts

Cipher Contracts is the smart-contract package for **Cipher** — a series of toolkits for building
confidential dApps on EVM chains. It lets Solidity developers add privacy-preserving features to
their apps without building the cryptography stack from scratch.

The first toolkit is the **DAO Toolkit**: confidential, OpenZeppelin-style governance where ballots
are FHE-encrypted ([Zama fhEVM](https://docs.zama.ai/)) and the tally stays encrypted until the DAO
decrypts the final result — with an **optional** zero-knowledge membership gate
([Noir](https://noir-lang.org/)) for anonymous, sybil-resistant eligibility.

> Like OpenZeppelin Contracts, this package ships **Solidity sources you inherit and deploy
> yourself**. Your app remains responsible for the off-chain parts (ZK proof generation, encrypted
> vote payloads, and KMS decryption inputs).

---

## Installation

```bash
npm install @privacy-protocol/cipher-contracts @openzeppelin/contracts @fhevm/solidity
```

Requires Solidity `^0.8.27`.

---

## Design: privacy by default, ZK by choice

`PrivateDaoAdapter` is a full confidential Governor. Confidentiality (encrypted ballots + tally) is
always on. The ZK membership gate is **optional and runtime-configurable** by the owner:

| Mode | How | Voting entrypoint |
| --- | --- | --- |
| **Confidential only** | deploy with no verifier (`address(0)`, `bytes32(0)` root) | `castEncryptedVote*` (inherited) |
| **Confidential + ZK gate** | deploy with a Noir verifier + membership root | `castEncryptedVoteWithMembershipProof` |

Switch modes after deployment with `setZkMembership(verifier, root)` (owner only). Read the current
mode with `zkMembershipEnabled()`.

---

## Usage

Deploy your own DAO by inheriting the adapter and supplying a confidential
[`IVotesConfidential`](src/Governance/interfaces/IVotesConfidential.sol) token (e.g. an
[ERC-7984](https://eips.ethereum.org/EIPS/eip-7984) votes token):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PrivateDaoAdapter} from "@privacy-protocol/cipher-contracts/src/DaoToolkit/PrivateDaoAdapter.sol";
import {IVotesConfidential} from "@privacy-protocol/cipher-contracts/src/Governance/interfaces/IVotesConfidential.sol";

contract MyDao is PrivateDaoAdapter {
    constructor(
        IVotesConfidential token,
        address voteSubmissionVerifier, // a Noir verifier, or address(0) to start ZK-disabled
        bytes32 membershipRoot          // the Poseidon2 root, or bytes32(0) when ZK-disabled
    ) PrivateDaoAdapter(token, voteSubmissionVerifier, membershipRoot) {}
}
```

To call a deployed adapter from another contract, import the interface instead:

```solidity
import {IPrivateDaoAdapter} from "@privacy-protocol/cipher-contracts/src/DaoToolkit/interface/IPrivateDaoAdapter.sol";
```

### The membership verifier

The ZK gate verifies a [Noir](https://noir-lang.org/) membership proof through a generated
`HonkVerifier` ([`src/DaoToolkit/VoteSubmissionVerifier.sol`](src/DaoToolkit/VoteSubmissionVerifier.sol),
which also declares the `IVerifier` interface and links `ZKTranscriptLib`).

- **Reuse ours** — a verifier matching the bundled circuit is already deployed (see
  [`deployments.json`](deployments.json)); point your DAO at that address. The verifier is shared,
  reusable infrastructure — there's no need to redeploy the multi-million-gas contract.
- **Bring your own** — this package intentionally does **not** ship the Noir circuit. If you want a
  different membership circuit, author it yourself, regenerate the verifier from it, and deploy that
  contract; pointing the adapter at it is all that's required on-chain.

### Deployments

[`deployments.json`](deployments.json) lists the canonical reusable contracts per network (the
membership verifier + its library). The DAO adapter itself is deploy-your-own.

```ts
import deployments from "@privacy-protocol/cipher-contracts/deployments.json";
const { HonkVerifier } = deployments["ethereum-sepolia"];
```

---

## End-to-end flow (ZK gate enabled)

1. Holders of the confidential votes `token` delegate to give themselves voting weight.
2. `propose(targets, values, calldatas, description)` opens a proposal (Governor-native).
3. Members vote with `castEncryptedVoteWithMembershipProof`, supplying an encrypted ballot, a Noir
   membership proof for the global `membershipRoot`, and a one-time nullifier.
4. After the deadline: `requestProposalResultDecryption` → fetch the KMS public decryption →
   `finalizeProposalResult` resolves `quorumReached` / `voteSucceeded`.
5. `execute(targets, values, calldatas, descriptionHash)` runs a succeeded proposal.

With the gate disabled, step 3 is just `castEncryptedVote` — no proof, no nullifier.

**Off-chain (your responsibility):** generating the Noir membership proof + nullifier, encrypting
the ballot into an fhEVM input, and obtaining the KMS decryption proof for finalization. This
package contains the on-chain Solidity only.

---

## Package contents

```
src/
  DaoToolkit/
    PrivateDaoAdapter.sol            confidential Governor + optional ZK gate (inherit this)
    VoteSubmissionVerifier.sol       generated Noir HonkVerifier + ZKTranscriptLib + IVerifier
    interface/IPrivateDaoAdapter.sol external interface for the adapter
  Governance/
    GovernorConfidential.sol
    GovernorCountingSimpleConfidential.sol
    GovernorVotesConfidential.sol
    GovernorVotesQuorumFractionConfidential.sol
    interfaces/IGovernorConfidential.sol
    interfaces/IVotesConfidential.sol
deployments.json
```

---

## Contribute

Contributions are welcome. Fork, branch, make focused changes (with tests where relevant), and open
a pull request. For major or security-relevant changes, open an issue first to discuss the design.

---

## License

MIT
