//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {IPrivateDaoAdapter} from "./interface/IPrivateDaoAdapter.sol";
import {IVerifier} from "./VoteSubmissionVerifier.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint8, euint64, externalEuint8} from "@fhevm/solidity/lib/FHE.sol";

/// @title PrivateDaoAdapter
/// @author Obaloluwa
/// @notice Stores proposal config, encrypted tallies, and nullifier replay protection.
contract PrivateDaoAdapter is IPrivateDaoAdapter, Ownable, ReentrancyGuard, ZamaEthereumConfig {
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    IVerifier public immutable voteSubmissionVerifier;
    address public proposalCreator;
    address public finalizer;

    mapping(uint256 proposalId => ProposalConfig proposal) public proposals;
    mapping(uint256 proposalId => mapping(bytes32 nullifierHash => bool used)) public nullifierUsed;
    mapping(uint256 proposalId => euint64[] eTallies) public encryptedTallies;
    mapping(uint256 proposalId => uint64[] rTallies) public revealedTallies;

    constructor(address _voteSubmissionVerifier) Ownable(msg.sender) {
        if (_voteSubmissionVerifier == address(0)) revert PDA__InvalidAddress();
        if (_voteSubmissionVerifier.code.length == 0) revert PDA__InvalidVerifier();

        voteSubmissionVerifier = IVerifier(_voteSubmissionVerifier);
        proposalCreator = msg.sender;
        finalizer = msg.sender;
    }

    modifier onlyProposalCreator() {
        if (msg.sender != owner() && msg.sender != proposalCreator) revert PDA__Unauthorized();
        _;
    }

    modifier onlyFinalizer() {
        if (msg.sender != owner() && msg.sender != finalizer) revert PDA__Unauthorized();
        _;
    }

    function setProposalCreator(address _proposalCreator) external onlyOwner {
        if (_proposalCreator == address(0)) revert PDA__InvalidAddress();

        address previousProposalCreator = proposalCreator;
        proposalCreator = _proposalCreator;

        emit PDA__ProposalCreatorUpdated(previousProposalCreator, _proposalCreator);
    }

    function setFinalizer(address _finalizer) external onlyOwner {
        if (_finalizer == address(0)) revert PDA__InvalidAddress();

        address previousFinalizer = finalizer;
        finalizer = _finalizer;

        emit PDA__FinalizerUpdated(previousFinalizer, _finalizer);
    }

    function _requireCanonicalField(bytes32 value) internal pure {
        if (uint256(value) >= SNARK_SCALAR_FIELD) revert PDA__FieldElementOutOfRange();
    }

    function _requireCanonicalField(uint256 value) internal pure {
        if (value >= SNARK_SCALAR_FIELD) revert PDA__FieldElementOutOfRange();
    }

    function propose(
        uint256 _proposalId,
        uint8 _ballotSize,
        uint64 _votingPeriod,
        bool _allowLiveReveal,
        bytes32 _membershipRoot
    ) external onlyProposalCreator returns (ProposalConfig memory proposal) {
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

        _requireCanonicalField(_proposalId);
        _requireCanonicalField(_membershipRoot);

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
        euint64[] storage proposalTallies = encryptedTallies[_proposalId];
        for (uint8 i = 0; i < _ballotSize;) {
            proposalTallies[i] = FHE.asEuint64(0);
            FHE.allowThis(proposalTallies[i]);
            unchecked {
                ++i;
            }
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
    ) external nonReentrant {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) revert PDA__ProposalNotExists();
        if (proposal.votingStart > block.timestamp) revert PDA__VotingPeriodNotStarted();
        if (block.timestamp > proposal.votingEnd) revert PDA__VotingPeriodEnded();
        if (proposal.ended) revert PDA__VotingAlreadyEnded();

        _requireCanonicalField(_nullifierHash);

        if (nullifierUsed[_proposalId][_nullifierHash]) revert PDA__NullifierAlreadyUsed();
        if (!_verifyVoteProof(_proposalId, proposal, _nullifierHash, _zkProof)) {
            revert PDA__InvalidVoteData();
        }

        nullifierUsed[_proposalId][_nullifierHash] = true;

        _tallyEncryptedVote(_proposalId, proposal.ballotSize, voteData);

        emit PDA__VoteSubmitted(_proposalId);
    }

    function getProposalById(uint256 _proposalId) external view returns (ProposalConfig memory proposal) {
        if (!proposals[_proposalId].exists) revert PDA__ProposalNotExists();

        return proposals[_proposalId];
    }

    function getRevealedTallies(uint256 _proposalId) external view returns (uint64[] memory tallies) {
        if (!proposals[_proposalId].exists) revert PDA__ProposalNotExists();
        if (!proposals[_proposalId].ended) revert PDA__ResultsNotRevealed();

        return revealedTallies[_proposalId];
    }

    function endVoting(
        uint256 _proposalId,
        bytes calldata abiEncodedResults,
        bytes calldata decryptionProof
    ) external onlyFinalizer nonReentrant {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) revert PDA__ProposalNotExists();
        if (block.timestamp < proposal.votingEnd) revert PDA__VotingPeriodNotEnded();
        if (proposal.ended) revert PDA__VotingAlreadyEnded();

        _makeTalliesPubliclyDecryptable(_proposalId, proposal.ballotSize);

        _revealFinalResults(_proposalId, abiEncodedResults, decryptionProof);
        proposal.ended = true;

        emit PDA__VotingEnded(_proposalId);
    }

    function getCurrentEncryptedTallies(
        uint256 _proposalId
    ) external view returns (bytes32[] memory currentEncryptedTallies) {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) revert PDA__ProposalNotExists();
        if (!proposal.allowLiveReveal) revert PDA__LiveRevealNotAllowed();
        if (proposal.ended) revert PDA__VotingPeriodEnded();

        currentEncryptedTallies = new bytes32[](proposal.ballotSize);
        euint64[] storage proposalTallies = encryptedTallies[_proposalId];
        for (uint8 i = 0; i < proposal.ballotSize;) {
            currentEncryptedTallies[i] = FHE.toBytes32(proposalTallies[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _revealFinalResults(
        uint256 _proposalId,
        bytes calldata abiEncodedResults,
        bytes calldata decryptionProof
    ) internal {
        ProposalConfig storage proposal = proposals[_proposalId];

        if (!proposal.exists) revert PDA__ProposalNotExists();
        if (block.timestamp < proposal.votingEnd) revert PDA__VotingPeriodNotEnded();

        uint64[] memory decodedResults = _revealVote(_proposalId, abiEncodedResults, decryptionProof);

        revealedTallies[_proposalId] = decodedResults;
        emit PDA__FinalResultsRevealed(_proposalId, decodedResults);
    }

    function _revealVote(
        uint256 _proposalId,
        bytes calldata abiEncodedResults,
        bytes calldata decryptionProof
    ) internal returns (uint64[] memory decryptedVotes) {
        ProposalConfig storage proposal = proposals[_proposalId];

        bytes32[] memory votes = new bytes32[](proposal.ballotSize);
        euint64[] storage proposalTallies = encryptedTallies[_proposalId];
        for (uint8 i = 0; i < proposal.ballotSize;) {
            votes[i] = FHE.toBytes32(proposalTallies[i]);
            unchecked {
                ++i;
            }
        }

        FHE.checkSignatures(votes, abiEncodedResults, decryptionProof);

        decryptedVotes = abi.decode(abiEncodedResults, (uint64[]));

        if (decryptedVotes.length != proposal.ballotSize) revert PDA__InvalidDecryptedTalliesLength();
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
        (bytes32 _encryptedVote, bytes memory _voteProof) = abi.decode(voteData, (bytes32, bytes));
        externalEuint8 extVote = externalEuint8.wrap(_encryptedVote);
        euint8 encryptedVote = FHE.fromExternal(extVote, _voteProof);

        euint64[] storage proposalTallies = encryptedTallies[_proposalId];
        for (uint8 i = 0; i < _ballotSize;) {
            ebool isThisOption = FHE.eq(encryptedVote, FHE.asEuint8(i));
            euint64 increment = FHE.select(isThisOption, FHE.asEuint64(1), FHE.asEuint64(0));

            proposalTallies[i] = FHE.add(proposalTallies[i], increment);
            FHE.allowThis(proposalTallies[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _makeTalliesPubliclyDecryptable(uint256 _proposalId, uint8 _ballotSize) internal {
        euint64[] storage proposalTallies = encryptedTallies[_proposalId];
        for (uint8 i = 0; i < _ballotSize;) {
            FHE.makePubliclyDecryptable(proposalTallies[i]);
            unchecked {
                ++i;
            }
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
