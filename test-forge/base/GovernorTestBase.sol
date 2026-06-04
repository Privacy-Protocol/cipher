// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {FHE, ebool, euint8, euint64, externalEuint8} from "@fhevm/solidity/lib/FHE.sol";

import {ConfigurableGovernor} from "../../contracts/contracts/mocks/ConfigurableGovernor.sol";
import {IVotesConfidential} from "../../contracts/contracts/Governance/interfaces/IVotesConfidential.sol";
import {MockConfidentialVotes} from "../mocks/MockConfidentialVotes.sol";

/// @dev Shared lifecycle helpers for the governance fuzz/invariant suites. Inherits {FhevmTest} so all
/// FHE encryption, log processing and decryption happen in this single instance (forge-fhevm's plaintext
/// DB and log cursor are per-instance).
abstract contract GovernorTestBase is FhevmTest {
    uint8 internal constant VOTE_AGAINST = 0;
    uint8 internal constant VOTE_FOR = 1;
    uint8 internal constant VOTE_ABSTAIN = 2;

    uint256 internal constant VOTING_DELAY = 7200;
    uint256 internal constant VOTING_PERIOD = 50400;

    MockConfidentialVotes internal token;
    ConfigurableGovernor internal governor;

    /// @notice Deploys the mock votes token and a {ConfigurableGovernor} with the given quorum numerator.
    function _deployGovernor(uint256 quorumNumerator) internal {
        token = new MockConfidentialVotes();
        governor = new ConfigurableGovernor(IVotesConfidential(address(token)), quorumNumerator);
        token.setGovernor(address(governor));
    }

    function _setVotes(address account, uint64 amount) internal {
        token.setVotes(account, amount);
    }

    // --- Proposal lifecycle ---

    function _defaultActions()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = "";
    }

    function _propose(address proposer, string memory description) internal returns (uint256 proposalId) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _defaultActions();
        proposalId = governor.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        vm.prank(proposer);
        governor.propose(targets, values, calldatas, description);
    }

    function _activate(uint256 proposalId) internal {
        vm.warp(governor.proposalSnapshot(proposalId) + 1);
    }

    function _advancePastDeadline(uint256 proposalId) internal {
        vm.warp(governor.proposalDeadline(proposalId) + 1);
    }

    /// @notice Encrypts `support` for `voter`, pranks as `voter`, and casts the encrypted vote.
    function _castVote(address voter, uint256 proposalId, uint8 support) internal {
        (externalEuint8 handle, bytes memory proof) = encryptUint8(support, voter, address(governor));
        vm.prank(voter);
        governor.castEncryptedVote(proposalId, handle, proof);
    }

    /// @notice Runs request → public-decrypt → finalize. The proposal deadline must already have passed.
    /// Decrypts the on-chain (quorumReached, voteSucceeded) ebools to obtain the true result, then signs
    /// and submits it the way the KMS would. Returns the finalized booleans.
    function _finalize(uint256 proposalId) internal returns (bool quorumReached, bool voteSucceeded) {
        governor.requestProposalResultDecryption(proposalId);
        return _completeFinalization(proposalId);
    }

    /// @notice Public-decrypt + finalize for a proposal whose decryption was already requested.
    function _completeFinalization(uint256 proposalId) internal returns (bool quorumReached, bool voteSucceeded) {
        (ebool encQuorum, ebool encSucceeded) = governor.encryptedProposalResult(proposalId);
        quorumReached = decrypt(encQuorum);
        voteSucceeded = decrypt(encSucceeded);

        bytes32[] memory handles = new bytes32[](2);
        handles[0] = ebool.unwrap(encQuorum);
        handles[1] = ebool.unwrap(encSucceeded);

        bytes memory abiEncodedResult = abi.encode(quorumReached, voteSucceeded);
        bytes memory decryptionProof = buildDecryptionProof(handles, abiEncodedResult);

        governor.finalizeProposalResult(proposalId, abiEncodedResult, decryptionProof);
    }

    // --- Tally decryption ---

    function _decryptVotes(uint256 proposalId)
        internal
        returns (uint64 againstVotes, uint64 forVotes, uint64 abstainVotes)
    {
        (euint64 against, euint64 forV, euint64 abstain) = governor.proposalVotes(proposalId);
        againstVotes = _decryptOrZero(against);
        forVotes = _decryptOrZero(forV);
        abstainVotes = _decryptOrZero(abstain);
    }

    /// @dev Uninitialized handles (bytes32(0)) have no plaintext entry; treat them as 0.
    function _decryptOrZero(euint64 handle) internal returns (uint64) {
        if (euint64.unwrap(handle) == bytes32(0)) {
            return 0;
        }
        return decrypt(handle);
    }

    // --- EIP-712 ballot signing ---

    function _eip712Digest(bytes32 structHash) internal view returns (bytes32) {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            governor.eip712Domain();
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
        return keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
    }

    function _sign(uint256 pk, bytes32 structHash) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _eip712Digest(structHash));
        return abi.encodePacked(r, s, v);
    }

    function _signEncryptedBallot(uint256 pk, uint256 proposalId, externalEuint8 support, bytes memory proof, address voter)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                governor.ENCRYPTED_BALLOT_TYPEHASH(),
                proposalId,
                support,
                keccak256(proof),
                voter,
                governor.nonces(voter)
            )
        );
        return _sign(pk, structHash);
    }

    function _signEncryptedExtendedBallot(
        uint256 pk,
        uint256 proposalId,
        externalEuint8 support,
        bytes memory proof,
        address voter,
        string memory reason,
        bytes memory params
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                governor.ENCRYPTED_EXTENDED_BALLOT_TYPEHASH(),
                proposalId,
                support,
                keccak256(proof),
                voter,
                governor.nonces(voter),
                keccak256(bytes(reason)),
                keccak256(params)
            )
        );
        return _sign(pk, structHash);
    }

    /// @dev Standard (cleartext) Ballot signature — used only to reach the cleartext-rejection revert.
    function _signCleartextBallot(uint256 pk, uint256 proposalId, uint8 support, address voter)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash =
            keccak256(abi.encode(governor.BALLOT_TYPEHASH(), proposalId, support, voter, governor.nonces(voter)));
        return _sign(pk, structHash);
    }

    function _signCleartextExtendedBallot(
        uint256 pk,
        uint256 proposalId,
        uint8 support,
        address voter,
        string memory reason,
        bytes memory params
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                governor.EXTENDED_BALLOT_TYPEHASH(),
                proposalId,
                support,
                voter,
                governor.nonces(voter),
                keccak256(bytes(reason)),
                keccak256(params)
            )
        );
        return _sign(pk, structHash);
    }
}
