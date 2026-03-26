# Cipher Contracts

Cipher Contracts is the smart contract package for **Cipher** — a series of toolkits for building confidential dApps on EVM blockchains.

The goal of Cipher is to help smart contract developers add privacy-preserving features to their dApps without having to build the entire cryptography stack from scratch.

---

## Overview

Cipher Contracts provides reusable Solidity contracts and toolkit modules for confidential application logic.

The first toolkit available is the **DAO Toolkit**, which is designed for private governance use cases such as - hidden votes onchain, encrypted tallying, private eligibility checks, nullifier-based replay protection. All these features are enabled through combining mathematical cryptography primitives like [ZK using Noir](https://noir-lang.org/) and [FHE using Zama](https://docs.zama.org/homepage).

More toolkits will be added over time to Cipher.

---

## Installation

Install Cipher Contracts in a Hardhat project with:

```bash
npm install @privacy-protocol/cipher-contracts @openzeppelin/contracts @fhevm/solidity
```

---

## Usage

`cipher-contracts` is designed to be used as a deployed adapter contract that your DAO or governance contract talks to, but you can also use our own deployments.

**Addresses:**

- `PrivateDaoAdapter`: `0x8274C53d82C5874455E67F80603F2792C9757cBE`
- `HonkVerifier`: `0x76A2d7a3F4927AaB90d2247eA541c305Ee8615F1`

Import the contract (for customization) or interface (quicker) into your Solidity code:

```solidity
import {PrivateDaoAdapter} from "@privacy-protocol/cipher-contracts/src/DaoToolkit/PrivateDaoAdapter.sol";
import {IPrivateDaoAdapter} from "@privacy-protocol/cipher-contracts/src/DaoToolkit/interface/IPrivateDaoAdapter.sol";
```

Check [Docs](https:www.privacyprotocol.org/docs) for example DAO integration pattern.

Note: this package contains the Solidity contracts only. Your application is still responsible for generating the zk proof, encrypted vote payload, and final decryption inputs expected by the adapter.

### What the DAO Toolkit provides

The DAO Toolkit is intended to support confidential governance flows such as:

- proposal registration with private voting config
- encrypted vote submission
- encrypted tally storage
- private membership verification
- nullifier-based one-vote enforcement
- final tally reveal

---

## Contribute

Contributions are welcome.

If you want to contribute:

1. Fork the repository
2. Create a new branch for your feature or fix
3. Make your changes
4. Add or update tests where necessary
5. Open a pull request

When contributing, please keep changes focused and clearly explain the reasoning behind architectural or security-related updates.

For major changes, it is best to open an issue first to discuss the proposal before implementation.

---

## License

MIT
