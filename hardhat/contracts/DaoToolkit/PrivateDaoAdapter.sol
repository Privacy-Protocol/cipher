//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {IPrivateDaoAdapter} from "./interface/IPrivateDaoAdapter.sol";
import {IVerifier} from "./VoteSubmissionVerifier.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint8, euint64, externalEuint8} from "@fhevm/solidity/lib/FHE.sol";

/// @title ProposalManager
/// @author Obaloluwa
/// @notice Stores proposal config, encrypted tallies, and nullifier replay protection.
contract PrivateDaoAdapter is IPrivateDaoAdapter, ZamaEthereumConfig {
    IVerifier public immutable voteSubmissionVerifier;

    mapping(uint256 proposalId => ProposalConfig proposal) public proposals;
    mapping(uint256 proposalId => mapping(bytes32 nullifierHash => bool used)) public nullifierUsed;
    mapping(uint256 proposalId => euint64[] eTallies) public encryptedTallies;
    mapping(uint256 proposalId => uint64[] rTallies) public revealedTallies;

    constructor(address _voteSubmissionVerifier) {
        voteSubmissionVerifier = IVerifier(_voteSubmissionVerifier);
    }

    function propose(
        uint256 _proposalId,
        uint8 _ballotSize,
        uint64 _votingPeriod,
        bool _allowLiveReveal,
        bytes32 _membershipRoot
    ) external returns (ProposalConfig memory proposal) {
        if (proposals[_proposalId].exists) {
            revert PDA__ProposalAlreadyExists();
        }

        if (_votingPeriod == 0) {
            revert PDA__InvalidVotingPeriod();
        }

        if (_ballotSize == 0 || _ballotSize > 16) {
            revert PDA__InvalidBallotSize();
        }

        if (_membershipRoot == bytes32(0)) {
            revert PDA__InvalidMembershipRoot();
        }

        proposals[_proposalId] = ProposalConfig({
            ballotSize: _ballotSize,
            votingStart: block.timestamp,
            votingEnd: block.timestamp + _votingPeriod,
            membershipRoot: _membershipRoot,
            ended: false,
            exists: true,
            allowLiveReveal: _allowLiveReveal
        });

        encryptedTallies[_proposalId] = new euint64[](_ballotSize);
        for (uint8 i = 0; i < _ballotSize; i++) {
            encryptedTallies[_proposalId][i] = FHE.asEuint64(0);
            FHE.allowThis(encryptedTallies[_proposalId][i]);
        }
        revealedTallies[_proposalId] = new uint64[](_ballotSize);

        emit PDA__ProposalCreated(_proposalId, _ballotSize, _votingPeriod);

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
            revert PDA__ProposalNotExists();
        }

        if (proposal.votingStart > block.timestamp) {
            revert PDA__VotingPeriodNotStarted();
        }

        if (block.timestamp > proposal.votingEnd) {
            revert PDA__VotingPeriodEnded();
        }

        if (nullifierUsed[_proposalId][_nullifierHash]) {
            revert PDA__NullifierAlreadyUsed();
        }

        if (!_verifyVoteProof(_proposalId, proposal, _nullifierHash, _zkProof)) {
            revert PDA__InvalidVoteProof();
        }

        nullifierUsed[_proposalId][_nullifierHash] = true;

        _tallyEncryptedVote(_proposalId, proposal.ballotSize, voteData);

        emit PDA__VoteSubmitted(_proposalId);
    }

    function getProposalById(uint256 _proposalId) external view returns (ProposalConfig memory proposal) {
        if (!proposals[_proposalId].exists) {
            revert PDA__ProposalNotExists();
        }

        return proposals[_proposalId];
    }

    function getRevealedTallies(uint256 _proposalId) external view returns (uint64[] memory tallies) {
        if (!proposals[_proposalId].exists) {
            revert PDA__ProposalNotExists();
        }

        return revealedTallies[_proposalId];
    }

    function endVoting(uint256 _proposalId, bytes memory abiEncodedResults, bytes memory decryptionProof) external {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) {
            revert PDA__ProposalNotExists();
        }

        if (block.timestamp < proposal.votingEnd) {
            revert PDA__VotingPeriodNotEnded();
        }

        if (proposal.ended) {
            revert PDA__VotingAlreadyEnded();
        }

        _makeTalliesPubliclyDecryptable(_proposalId, proposal.ballotSize);

        _revealFinalResults(_proposalId, abiEncodedResults, decryptionProof);
        proposal.ended = true;

        emit PDA__VotingEnded(_proposalId);
    }

    function revealAggregateTallies(
        uint256 _proposalId,
        bytes memory abiEncodedResults,
        bytes memory decryptionProof
    ) external returns (uint64[] memory) {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) {
            revert PDA__ProposalNotExists();
        }

        uint64[] memory decryptedTallies = new uint64[](proposal.ballotSize);

        if (block.timestamp < proposal.votingEnd) {
            if (proposal.allowLiveReveal) {
                _makeTalliesPubliclyDecryptable(_proposalId, proposal.ballotSize);
                decryptedTallies = _revealVote(_proposalId, abiEncodedResults, decryptionProof);
                emit PDA__AggregateResultsRevealed(_proposalId, decryptedTallies);
                return decryptedTallies;
            } else {
                revert PDA__VotingPeriodNotEnded();
            }
        }

        decryptedTallies = _revealVote(_proposalId, abiEncodedResults, decryptionProof);

        emit PDA__AggregateResultsRevealed(_proposalId, decryptedTallies);
        return decryptedTallies;
    }

    function _revealFinalResults(
        uint256 _proposalId,
        bytes memory abiEncodedResults,
        bytes memory decryptionProof
    ) internal {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) {
            revert PDA__ProposalNotExists();
        }

        if (block.timestamp < proposal.votingEnd) {
            revert PDA__VotingPeriodNotEnded();
        }

        uint64[] memory decodedResults = _revealVote(_proposalId, abiEncodedResults, decryptionProof);

        revealedTallies[_proposalId] = decodedResults;
        emit PDA__FinalResultsRevealed(_proposalId, decodedResults);
    }

    function _revealVote(
        uint256 _proposalId,
        bytes memory abiEncodedResults,
        bytes memory decryptionProof
    ) internal returns (uint64[] memory decryptedVotes) {
        ProposalConfig storage proposal = proposals[_proposalId];

        bytes32[] memory votes = new bytes32[](proposal.ballotSize);
        for (uint8 i = 0; i < proposal.ballotSize; i++) {
            votes[i] = FHE.toBytes32(encryptedTallies[_proposalId][i]);
        }

        FHE.checkSignatures(votes, abiEncodedResults, decryptionProof);

        decryptedVotes = abi.decode(abiEncodedResults, (uint64[]));
        if (decryptedVotes.length != proposal.ballotSize) {
            revert PDA__InvalidDecryptedTalliesLength();
        }
    }

    function _verifyVoteProof(
        uint256 _proposalId,
        ProposalConfig storage proposal,
        bytes32 _nullifierHash,
        bytes calldata _zkProof
    ) internal returns (bool) {
        bytes32[] memory publicInputs = _buildCircuitPublicInputs(_proposalId, proposal, _nullifierHash);
        return voteSubmissionVerifier.verify(_zkProof, publicInputs);
    }

    function _tallyEncryptedVote(uint256 _proposalId, uint8 _ballotSize, bytes calldata voteData) internal {
        // TODO: add voter weight. for now its all 1 per vote.
        bytes32 _encryptedVote;
        bytes memory _voteProof;

        try this.decodeVoteData(voteData) returns (bytes32 encryptedVote_, bytes memory voteProof_) {
            _encryptedVote = encryptedVote_;
            _voteProof = voteProof_;
        } catch {
            revert PDA__InvalidVoteProof();
        }
        externalEuint8 extVote = externalEuint8.wrap(_encryptedVote);
        euint8 encryptedVote = FHE.fromExternal(extVote, _voteProof);

        for (uint8 i = 0; i < _ballotSize; i++) {
            ebool isThisOption = FHE.eq(encryptedVote, FHE.asEuint8(i));
            euint64 increment = FHE.select(isThisOption, FHE.asEuint64(1), FHE.asEuint64(0));

            encryptedTallies[_proposalId][i] = FHE.add(encryptedTallies[_proposalId][i], increment);
            FHE.allowThis(encryptedTallies[_proposalId][i]);
        }
    }

    function decodeVoteData(
        bytes calldata voteData
    ) external pure returns (bytes32 encryptedVote, bytes memory voteProof) {
        return abi.decode(voteData, (bytes32, bytes));
    }

    function _makeTalliesPubliclyDecryptable(uint256 _proposalId, uint8 _ballotSize) internal {
        for (uint8 i = 0; i < _ballotSize; i++) {
            FHE.makePubliclyDecryptable(encryptedTallies[_proposalId][i]);
        }
    }

    function _buildCircuitPublicInputs(
        uint256 _proposalId,
        ProposalConfig storage proposal,
        bytes32 _nullifierHash
    ) internal view returns (bytes32[] memory publicInputs) {
        publicInputs = new bytes32[](4);
        publicInputs[0] = bytes32(_proposalId);
        publicInputs[1] = proposal.membershipRoot;
        publicInputs[2] = bytes32(uint256(proposal.ballotSize));
        publicInputs[3] = _nullifierHash;
    }
}
