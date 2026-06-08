// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IVotesConfidential} from "../../Governance/interfaces/IVotesConfidential.sol";
import {PrivateDaoAdapter} from "../../DaoToolkit/PrivateDaoAdapter.sol";

/**
 * @title DemoDao
 * @notice A concrete confidential, membership-gated DAO built on {PrivateDaoAdapter}.
 * @dev DemoDao is a thin deployment of the adapter: it inherits the full confidential Governor
 *      so proposers and voters interact with this contract directly (voting weight and replay
 *      protection are bound to `msg.sender`, so the adapter cannot be safely wrapped/relayed).
 *
 *      End-to-end flow:
 *        1. Holders of the confidential votes `token` delegate, giving themselves voting weight.
 *        2. `propose(targets, values, calldatas, description)` opens a proposal (Governor-native).
 *        3. Members vote via `castEncryptedVoteWithMembershipProof`, supplying a Noir merkle-
 *           membership proof for the global `membershipRoot` plus a one-time nullifier.
 *        4. After the deadline, `requestProposalResultDecryption` then `finalizeProposalResult`
 *           decrypt the encrypted tally into `quorumReached` / `voteSucceeded`.
 *        5. `execute(targets, values, calldatas, descriptionHash)` runs a succeeded proposal.
 *
 *      Governance parameters (voting delay/period, quorum fraction) come from the adapter.
 */
contract DemoDao is PrivateDaoAdapter {
    constructor(
        IVotesConfidential token,
        address voteSubmissionVerifier,
        bytes32 membershipRoot
    ) PrivateDaoAdapter(token, voteSubmissionVerifier, membershipRoot) {}
}
