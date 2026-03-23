//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {IProposalManager} from "./interface/IProposalManager.sol";
import {HonkVerifier} from "./VoteSubmissionVerifier.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint8, euint64, externalEuint8} from "@fhevm/solidity/lib/FHE.sol";

/// @title ProposalManager
/// @author Obaloluwa
/// @notice Stores proposal config, encrypted tallies, and nullifier replay protection.
contract ProposalManager is IProposalManager, ZamaEthereumConfig {
    HonkVerifier public immutable voteSubmissionVerifier;

    mapping(uint256 proposalId => ProposalConfig proposal) public proposals;
    mapping(uint256 proposalId => mapping(bytes32 nullifierHash => bool used)) public nullifierUsed;
    mapping(uint256 proposalId => euint64[] eTallies) public encryptedTallies;
    mapping(uint256 proposalId => uint64[] rTallies) public revealedTallies;

    constructor() {
        voteSubmissionVerifier = new HonkVerifier();
    }

    function propose(
        uint256 _proposalId,
        uint8 _ballotSize,
        uint64 _votingPeriod,
        bool _allowLiveReveal,
        bytes32 _membershipRoot
    ) external returns (ProposalConfig memory proposal) {
        if (proposals[_proposalId].exists) {
            revert ProposalManager__ProposalAlreadyExists();
        }

        if (_votingPeriod == 0) {
            revert ProposalManager__InvalidVotingPeriod();
        }

        if (_ballotSize == 0 || _ballotSize > 16) {
            revert ProposalManager__InvalidBallotSize();
        }

        if (_membershipRoot == bytes32(0)) {
            revert ProposalManager__InvalidMembershipRoot();
        }

        proposals[_proposalId] = ProposalConfig({
            ballotSize: _ballotSize,
            votingStart: block.timestamp,
            votingEnd: block.timestamp + _votingPeriod,
            membershipRoot: _membershipRoot,
            exists: true,
            allowLiveReveal: _allowLiveReveal,
            voteCounts: new uint256[](_ballotSize)
        });

        encryptedTallies[_proposalId] = new euint64[](_ballotSize);
        revealedTallies[_proposalId] = new uint64[](_ballotSize);

        emit ProposalCreated(_proposalId, _ballotSize, _votingPeriod);

        return proposals[_proposalId];
    }

    function submitEncryptedVote(
        uint256 _proposalId,
        bytes32 _nullifierHash,
        bytes calldata _zkProof,
        bytes calldata voteData
    ) external {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) {
            revert ProposalManager__ProposalNotExists();
        }

        if (block.timestamp > proposal.votingEnd) {
            revert ProposalManager__VotingPeriodEnded();
        }

        if (nullifierUsed[_proposalId][_nullifierHash]) {
            revert ProposalManager__NullifierAlreadyUsed();
        }

        if (!_verifyVoteProof(_proposalId, proposal, _nullifierHash, _zkProof)) {
            revert ProposalManager__InvalidVoteProof();
        }

        _tallyEncryptedVote(_proposalId, proposal.ballotSize, voteData);

        nullifierUsed[_proposalId][_nullifierHash] = true;

        emit VoteSubmitted(_proposalId);
    }

    function getProposalById(uint256 _proposalId) external view returns (ProposalConfig memory proposal) {
        if (!proposals[_proposalId].exists) {
            revert ProposalManager__ProposalNotExists();
        }

        return proposals[_proposalId];
    }

    function endVoting(uint256 _proposalId, bytes memory abiEncodedResults, bytes memory decryptionProof) external {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) {
            revert ProposalManager__ProposalNotExists();
        }

        if (block.timestamp < proposal.votingEnd) {
            revert ProposalManager__VotingPeriodNotEnded();
        }

        for (uint8 i = 0; i < proposal.ballotSize; i++) {
            FHE.makePubliclyDecryptable(encryptedTallies[_proposalId][i]);
        }

        emit VotingEnded(_proposalId);

        _revealFinalResults(_proposalId, abiEncodedResults, decryptionProof);
    }

    function revealAggregateTallies(uint256 _proposalId, bytes memory abiEncodedResults, bytes memory decryptionProof)
        external
        returns (uint64[] memory decryptedTallies)
    {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) {
            revert ProposalManager__ProposalNotExists();
        }

        if (block.timestamp < proposal.votingEnd) {
            if (proposal.allowLiveReveal) {
                decryptedTallies = _revealVote(_proposalId, abiEncodedResults, decryptionProof);
            } else {
                revert ProposalManager__VotingPeriodNotEnded();
            }
        }

        decryptedTallies = _revealVote(_proposalId, abiEncodedResults, decryptionProof);

        emit AggregateResultsRevealed(_proposalId, decryptedTallies);
    }

    function _revealFinalResults(uint256 _proposalId, bytes memory abiEncodedResults, bytes memory decryptionProof)
        internal
    {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) {
            revert ProposalManager__ProposalNotExists();
        }

        if (block.timestamp < proposal.votingEnd) {
            revert ProposalManager__VotingPeriodNotEnded();
        }

        uint64[] memory decodedResults = _revealVote(_proposalId, abiEncodedResults, decryptionProof);

        revealedTallies[_proposalId] = decodedResults;

        for (uint8 i = 0; i < proposal.ballotSize; i++) {
            proposal.voteCounts[i] = decodedResults[i];
        }

        emit FinalResultsRevealed(_proposalId, proposal.voteCounts);
    }

    function _revealVote(uint256 _proposalId, bytes memory abiEncodedResults, bytes memory decryptionProof)
        internal
        returns (uint64[] memory decryptedVotes)
    {
        ProposalConfig storage proposal = proposals[_proposalId];

        bytes32[] memory votes = new bytes32[](proposal.ballotSize);
        for (uint8 i = 0; i < proposal.ballotSize; i++) {
            votes[i] = FHE.toBytes32(encryptedTallies[_proposalId][i]);
        }

        FHE.checkSignatures(votes, abiEncodedResults, decryptionProof);

        // TODO: check if the decrypted votes are same length as encrypted votes
        decryptedVotes = abi.decode(abiEncodedResults, (uint64[]));
    }

    function _verifyVoteProof(
        uint256 _proposalId,
        ProposalConfig storage proposal,
        bytes32 _nullifierHash,
        bytes calldata _zkProof
    ) internal view returns (bool) {
        bytes32[] memory publicInputs = _buildCircuitPublicInputs(_proposalId, proposal, _nullifierHash);
        return voteSubmissionVerifier.verify(_zkProof, publicInputs);
    }

    function _tallyEncryptedVote(uint256 _proposalId, uint8 _ballotSize, bytes calldata voteData) internal {
        // TODO: add voter weight. for now its all 1 per vote.
        (bytes32 _encryptedVote, bytes memory _voteProof) = abi.decode(voteData, (bytes32, bytes));
        externalEuint8 extVote = externalEuint8.wrap(_encryptedVote);
        euint8 encryptedVote = FHE.fromExternal(extVote, _voteProof);

        for (uint8 i = 0; i < _ballotSize; i++) {
            ebool isThisOption = FHE.eq(encryptedVote, FHE.asEuint8(i));
            euint64 increment = FHE.select(isThisOption, FHE.asEuint64(1), FHE.asEuint64(0));

            encryptedTallies[_proposalId][i] = FHE.add(encryptedTallies[_proposalId][i], increment);
            FHE.allowThis(encryptedTallies[_proposalId][i]);
        }
    }

    function _buildCircuitPublicInputs(uint256 _proposalId, ProposalConfig storage proposal, bytes32 _nullifierHash)
        internal
        view
        returns (bytes32[] memory publicInputs)
    {
        publicInputs = new bytes32[](4);
        publicInputs[0] = bytes32(_proposalId);
        publicInputs[1] = proposal.membershipRoot;
        publicInputs[2] = bytes32(uint256(proposal.ballotSize));
        publicInputs[3] = _nullifierHash;
    }
}
