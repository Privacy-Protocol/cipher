//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {IProposalManager} from "./interface/IProposalManager.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint8, euint64, externalEuint8} from "@fhevm/solidity/lib/FHE.sol";

/// @title ProposalManager
/// @author Obaloluwa
/// @notice Stores config for each proposal.``
contract ProposalManager is IProposalManager, ZamaEthereumConfig {
    // bytes32 membershipRoot;          // Merkle root of eligible voters
    // bytes32 tallyEncryptionKeyRef;   // Ref/hash/id for tally pubkey or params

    mapping(uint proposalId => ProposalConfig proposal) public proposals;
    // TODO: consider making this encrypted or ZK with nullifier
    mapping(uint proposalId => mapping(address user => bool voted)) public hasVoted;
    mapping(uint proposalId => euint64[] eTallies) public encryptedTallies;
    mapping(uint proposalId => uint64[] rTallies) public revealedTallies;

    function propose(
        uint _proposalId,
        uint8 _ballotSize,
        uint64 _votingPeriod,
        bool _allowLiveReveal
    ) external returns (ProposalConfig memory proposal) {
        if (proposals[_proposalId].exists) {
            revert ProposalManager__ProposalAlreadyExists();
        }

        if (_votingPeriod == 0) {
            revert ProposalManager__InvalidVotingPeriod();
        }

        if (_ballotSize == 0) {
            revert ProposalManager__InvalidBallotSize();
        }

        if (_ballotSize > 16) {
            revert ProposalManager__InvalidBallotSize();
        }

        proposals[_proposalId] = ProposalConfig({
            ballotSize: _ballotSize,
            votingStart: block.timestamp,
            votingEnd: block.timestamp + _votingPeriod,
            allowLiveReveal: _allowLiveReveal,
            voteCounts: new uint[](_ballotSize),
            exists: true
        });

        encryptedTallies[_proposalId] = new euint64[](_ballotSize);
        revealedTallies[_proposalId] = new uint64[](_ballotSize);

        emit ProposalCreated(_proposalId, _ballotSize, _votingPeriod);

        return proposals[_proposalId];
    }

    function submitEncryptedVote(uint _proposalId, address voter, bytes calldata voteData) external {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) {
            revert ProposalManager__ProposalNotExists();
        }

        if (block.timestamp > proposal.votingEnd) {
            revert ProposalManager__VotingPeriodEnded();
        }

        // TODO: add logic to check if the voter is eligible to vote
        // TODO: this logic to check if the voter has already voted should be ZK with nullifier??
        if (hasVoted[_proposalId][voter]) {
            revert ProposalManager__UserAlreadyVoted();
        }

        // TODO: add voter weight. for now its all 1 per vote

        (bytes32 _encryptedVote, bytes memory _voteProof) = abi.decode(voteData, (bytes32, bytes));
        externalEuint8 extVote = externalEuint8.wrap(_encryptedVote);

        euint8 encryptedVote = FHE.fromExternal(extVote, _voteProof);

        for (uint8 i = 0; i < proposal.ballotSize; i++) {
            ebool isThisOption = FHE.eq(encryptedVote, FHE.asEuint8(i));

            euint64 increment = FHE.select(isThisOption, FHE.asEuint64(1), FHE.asEuint64(0));

            encryptedTallies[_proposalId][i] = FHE.add(encryptedTallies[_proposalId][i], increment);
            FHE.allowThis(encryptedTallies[_proposalId][i]);
        }

        hasVoted[_proposalId][voter] = true;

        emit VoteSubmitted(_proposalId);
    }

    function getProposalById(uint _proposalId) external view returns (ProposalConfig memory proposal) {
        if (!proposals[_proposalId].exists) {
            revert ProposalManager__ProposalNotExists();
        }

        return proposals[_proposalId];
    }

    function endVoting(uint _proposalId, bytes memory abiEncodedResults, bytes memory decryptionProof) external {
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

    function revealAggregateTallies(
        uint _proposalId,
        bytes memory abiEncodedResults,
        bytes memory decryptionProof
    ) external returns (uint64[] memory decryptedTallies) {
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

    function _revealFinalResults(
        uint _proposalId,
        bytes memory abiEncodedResults,
        bytes memory decryptionProof
    ) internal {
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

    function _revealVote(
        uint _proposalId,
        bytes memory abiEncodedResults,
        bytes memory decryptionProof
    ) internal returns (uint64[] memory decryptedVotes) {
        ProposalConfig storage proposal = proposals[_proposalId];

        bytes32[] memory votes = new bytes32[](proposal.ballotSize);
        for (uint8 i = 0; i < proposal.ballotSize; i++) {
            votes[i] = FHE.toBytes32(encryptedTallies[_proposalId][i]);
        }

        FHE.checkSignatures(votes, abiEncodedResults, decryptionProof);

        // TODO: check if the decrypted votes are same length as encrypted votes
        decryptedVotes = abi.decode(abiEncodedResults, (uint64[]));
    }
}
