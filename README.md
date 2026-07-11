# Cipher

**Reusable confidential smart contracts for EVM chains — think OpenZeppelin, for privacy.**

[![npm](https://img.shields.io/npm/v/%40privacy-protocol%2Fcipher-contracts)](https://www.npmjs.com/package/@privacy-protocol/cipher-contracts)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.27-363636)](https://docs.soliditylang.org)
[![Network: Sepolia](https://img.shields.io/badge/Network-Sepolia-8A2BE2)](#deployments)

Cipher is a privacy middleware toolkit for building **confidential decentralized applications**. It packages advanced cryptography — **Zero-Knowledge proofs** (Noir + UltraHonk) and **Fully Homomorphic Encryption** (Zama fhEVM) — into reusable Solidity contracts you inherit and deploy, so you can add private data, proof-based validation, and encrypted computation to your app **without designing privacy infrastructure from scratch**.

Cipher is part of [Privacy Protocol](https://www.privacyprotocol.org), a suite of open-source privacy tooling for EVM chains — alongside [Beacon](https://github.com/Privacy-Protocol/beacon) (ZK proof oracle) and [Cloak](https://github.com/Privacy-Protocol/cloak-sdk) (anonymous transactions SDK).

📚 **Full documentation:** [privacyprotocol.org/docs/cipher](https://www.privacyprotocol.org/docs/cipher)

---

## The adapter model

Cipher is organized into **domain-specific adapters** — contract toolkits you inherit the same way you'd extend OpenZeppelin's `Governor` or `ERC20`. Each adapter packages the right privacy architecture for a real application category, on two proven foundations:

| Foundation | Technology | Role |
| --- | --- | --- |
| Fully Homomorphic Encryption | [Zama fhEVM](https://docs.zama.ai) | Encrypted state and computation — operate on ciphertext without decrypting it |
| Zero-Knowledge proofs | [Noir](https://noir-lang.org) + UltraHonk | Prove eligibility, validity, and rules without revealing the underlying data |

| Adapter | Status | What it gives you |
| --- | --- | --- |
| **Private DAO Adapter** | ✅ Available | Confidential governance: FHE-encrypted ballots, encrypted tallying, optional anonymous ZK membership gate |
| RWA Adapter | 🔜 Planned | Confidential real-world-asset flows: encrypted balances + ZK transfer-eligibility |
| More adapters | 🔜 Planned | Sealed-bid auctions, private payroll/vesting, … ([roadmap](#roadmap)) |

## Quick start — a confidential DAO in ~10 lines

### 1. Install

```bash
npm install @privacy-protocol/cipher-contracts @openzeppelin/contracts @fhevm/solidity
```

### 2. Inherit the adapter

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PrivateDaoAdapter} from "@privacy-protocol/cipher-contracts/src/DaoToolkit/PrivateDaoAdapter.sol";
import {IVotesConfidential} from "@privacy-protocol/cipher-contracts/src/Governance/interfaces/IVotesConfidential.sol";

contract MyDao is PrivateDaoAdapter {
    constructor(
        IVotesConfidential token,       // your confidential votes token (ERC-7984 style)
        address membershipVerifier,     // reusable Sepolia verifier, or address(0) for FHE-only mode
        bytes32 membershipRoot          // Poseidon2 member-set root, or bytes32(0)
    ) PrivateDaoAdapter(token, membershipVerifier, membershipRoot) {}
}
```

### 3. Deploy

```typescript
// With the anonymous ZK membership gate (reuses the canonical Sepolia verifier):
const dao = await MyDao.deploy(TOKEN, "0x6554ebdBc25e9023BC80006775958be57f8d8ea1", MEMBERSHIP_ROOT);

// Or start confidential-only and enable the gate later with setZkMembership():
const dao = await MyDao.deploy(TOKEN, ethers.ZeroAddress, ethers.ZeroHash);
```

You now have an OpenZeppelin-style Governor where **the cleartext vote never touches the chain**: ballots are FHE ciphertexts, tallies accumulate encrypted, and only the final two result booleans are ever decrypted.

The docs walk through the full lifecycle — [building your DAO](https://www.privacyprotocol.org/docs/cipher/adapters/private-dao-adapter/build), [membership & proving kits](https://www.privacyprotocol.org/docs/cipher/adapters/private-dao-adapter/membership), [proofs & encryption off-chain](https://www.privacyprotocol.org/docs/cipher/adapters/private-dao-adapter/proofs), and [deployment](https://www.privacyprotocol.org/docs/cipher/adapters/private-dao-adapter/deployment).

## Private DAO Adapter — features

**Privacy by default, ZK by choice.** Deploy with no verifier for confidential voting, or add the ZK gate for full anonymity — and toggle it at runtime with `setZkMembership()` without migrating.

- **Encrypted ballots** — votes submitted as FHE ciphertext (`externalEuint8`); 0/1/2 choices never appear in plaintext on-chain
- **Encrypted homomorphic tally** — Against / For / Abstain accumulate as `euint64` under FHE
- **Token-weighted voting** — weight from a confidential ERC-7984 votes token (delegation-based)
- **Encrypted quorum** — quorum checked against encrypted total supply
- **Optional anonymous membership gate** — Noir proof over a depth-32 Poseidon2 Merkle tree proves eligibility without revealing *which* member is voting
- **One-time nullifiers** — `Poseidon2(proposalId, identitySecret)` stops a member voting twice, even from different wallets
- **Two-phase result decryption** — request → KMS public decryption → finalize; only `quorumReached` and `voteSucceeded` are revealed
- **Standard Governor lifecycle** — `propose` / `state` / `execute`, built on OpenZeppelin Governor

Under the hood the adapter composes reusable mixins you can also build on directly: `GovernorConfidential`, `GovernorCountingSimpleConfidential`, `GovernorVotesConfidential`, `GovernorVotesQuorumFractionConfidential`, plus an [`ERC7984`](contracts/contracts/Tokens/ERC7984.sol) confidential votes token reference implementation.

## Deployments

### Ethereum Sepolia (chain id `11155111`) — reusable infrastructure

| Contract | Address |
| --- | --- |
| `HonkVerifier` (membership) | [`0x6554ebdBc25e9023BC80006775958be57f8d8ea1`](https://sepolia.etherscan.io/address/0x6554ebdBc25e9023BC80006775958be57f8d8ea1) |
| `ZKTranscriptLib` | [`0xa567D41325Cfc5670827eCfDc980f7e381791d27`](https://sepolia.etherscan.io/address/0xa567D41325Cfc5670827eCfDc980f7e381791d27) |

These are shared infrastructure — every Cipher DAO on Sepolia can point at the same verifier. Your DAO and token are contracts **you** deploy (see [Quick start](#quick-start--a-confidential-dao-in-10-lines)). Canonical addresses also ship inside the npm package (`deployments.json`). Ethereum mainnet and L2 deployments are planned ([roadmap](#roadmap)).

## Repository layout

| Path | What it is |
| --- | --- |
| [`contracts/contracts/DaoToolkit/`](contracts/contracts/DaoToolkit) | `PrivateDaoAdapter`, generated membership verifier, interfaces |
| [`contracts/contracts/Governance/`](contracts/contracts/Governance) | Confidential Governor mixins + interfaces |
| [`contracts/contracts/Tokens/`](contracts/contracts/Tokens) | `ERC7984` confidential votes token |
| [`contracts/contracts/demo/`](contracts/contracts/demo) | `DemoDao` — concrete reference deployment |
| [`circuits/`](circuits) | Noir membership circuit (Poseidon2 Merkle inclusion + nullifier) |
| [`sdk/cipher-contracts/`](sdk/cipher-contracts) | The published npm package (Solidity sources + canonical deployments) |
| [`examples/hardhat/`](examples/hardhat) | Example Hardhat project consuming the package |
| [`test-forge/`](test-forge) | Foundry fuzz/invariant suite for the Governor stack |

## Development

### Prerequisites

- Node.js ≥ 20, npm ≥ 7
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (for the fuzz/invariant suite)
- [Noir](https://noir-lang.org/docs/getting_started/quick_start) `1.0.0-beta.16` (only if changing circuits)

### Build & test

```bash
git clone https://github.com/Privacy-Protocol/cipher.git
cd cipher
npm install

# Solidity (Hardhat): compile + full confidential-Governor test suite (65 tests)
cd contracts
npm run compile
npm run test

# Foundry fuzz/invariant suite (49 tests), from the repo root
cd .. && forge test

# Noir circuit (only when modifying it)
cd circuits && nargo build
```

### Deploy

```bash
cd contracts
npm run deploy:localhost          # local hardhat node
npm run deploy:sepolia            # needs MNEMONIC + ALCHEMY_API_KEY configured
npm run verify:sepolia <ADDRESS>  # Etherscan verification
```

### Toolchain pins

| Dependency | Version |
| --- | --- |
| Solidity | `^0.8.27` (Cancun EVM) |
| `@fhevm/solidity` | `^0.11.1` |
| `@openzeppelin/contracts` | `^5.6.1` |
| `@noir-lang/noir_js` | `1.0.0-beta.16` |
| `@aztec/bb.js` | `3.0.0-nightly.20251104` |
| `@zama-fhe/relayer-sdk` | `^0.4.1` |

> ⚠️ The Noir/Aztec pins are exact for a reason: proofs generated with other versions will not verify against the deployed verifier.

## Security & trust model

- **Vote privacy** rests on Zama's fhEVM: individual ballots and running tallies are never decrypted; only the final result booleans are revealed via the KMS two-phase flow.
- **Voter anonymity** (with the ZK gate) rests on SNARK soundness: the membership proof reveals nothing beyond "a member of this set voted", and the nullifier prevents double-voting.
- **Testnet only.** Deployed to Sepolia; do not govern real value with it yet.
- **Not yet audited.** The contracts and circuit have not undergone a formal third-party audit.

Found a vulnerability? Please report it privately via GitHub security advisories rather than a public issue.

## Roadmap

- **RWA Adapter** — confidential real-world-asset issuance and transfers: encrypted balances (ERC-7984) with ZK transfer-eligibility proofs
- **More adapters** — sealed-bid auctions (FHE bids), private payroll/vesting
- **Contract wizard** — an OpenZeppelin-Wizard-style configurator on [privacyprotocol.org](https://www.privacyprotocol.org) that generates your adapter deployment code
- **Beacon integration** — adapters verifying membership through the shared [Beacon](https://github.com/Privacy-Protocol/beacon) `VerifierHub`
- **Mainnet + L2 deployments** after audit and multisig governance

## Contributing

Cipher is open source (MIT) and contributions are very welcome — this project is built to be a public good for the Ethereum ecosystem.

1. Fork the repository and create a feature branch
2. Make your changes; add or update tests (`npm run test` and `forge test` must pass)
3. Open a pull request explaining the motivation — for security- or architecture-affecting changes, please open an issue first to discuss

Good first contributions: new adapter proposals, gas benchmarks, docs and examples, additional fuzz targets.

## Community

- Website & docs: [privacyprotocol.org](https://www.privacyprotocol.org)
- X / Twitter: [@BuildOnPrivacy](https://x.com/BuildOnPrivacy)
- Telegram: [t.me/buildonprivacy](https://t.me/buildonprivacy)
- Discord: [discord.gg/aCmAGWaB](https://discord.gg/aCmAGWaB)

## License

[MIT](./LICENSE) © 2026 Privacy Protocol
