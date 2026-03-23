// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IProposalManager} from "../../DaoToolkit/interface/IProposalManager.sol";

/**
 * @title DemoDao
 * @notice A simple DAO contract that allows members to create proposals, vote, execute, and close proposals
 * @dev Members are defined by holding a minimum amount of governance tokens
 */
contract DemoDao is ReentrancyGuard {
    // ============ Errors ============
    error DemoDao__NotAMember();
    error DemoDao__ProposalDoesNotExist();
    error DemoDao__ProposalNotActive();
    error DemoDao__ProposalStillActive();
    error DemoDao__ProposalAlreadyExecuted();
    error DemoDao__ProposalNotPassed();
    error DemoDao__VotingPeriodEnded();
    error DemoDao__ExecutionFailed();
    error DemoDao__InvalidVotingPeriod();
    error DemoDao__InvalidQuorum();
    error DemoDao__AddressZero();
    error DemoDao__InsufficientTokenBalance();

    // ============ Types ============
    enum ProposalStatus {
        Active,
        Passed,
        Failed,
        Executed,
        Closed
    }

    struct ProposalCore {
        address proposer;
        address target;
        uint256 value;
        uint256 startTime;
        uint256 endTime;
        ProposalStatus status;
        bool executed;
    }

    // ============ Events ============
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address target,
        uint256 startTime,
        uint256 endTime
    );

    event VoteCast(uint256 indexed proposalId, address indexed voter, uint8 support, uint256 weight);

    event ProposalExecuted(uint256 indexed proposalId, bool success);
    event ProposalClosed(uint256 indexed proposalId, ProposalStatus status);

    // ============ State Variables ============
    IERC20 public immutable GOVERNANCE_TOKEN;
    IProposalManager public immutable PROPOSAL_MANAGER;

    uint256 public immutable MIN_TOKENS_TO_PROPOSE;
    uint256 public immutable MIN_TOKENS_TO_VOTE;
    uint256 public immutable VOTING_PERIOD;
    uint256 public immutable QUORUM_PERCENTAGE;

    uint256 public s_proposalCount;
    mapping(uint256 => ProposalCore) public s_proposals;
    mapping(uint256 => bytes) public s_proposalData;
    // ============ Modifiers ============
    modifier onlyMember() {
        _checkMember();
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        _checkProposalExists(proposalId);
        _;
    }

    // ============ Constructor ============
    constructor(
        address _governanceToken,
        address _proposalManager,
        uint256 _minTokensToPropose,
        uint256 _minTokensToVote,
        uint256 _votingPeriod,
        uint256 _quorumPercentage
    ) {
        if (_governanceToken == address(0) || _proposalManager == address(0)) {
            revert DemoDao__AddressZero();
        }
        if (_votingPeriod == 0) {
            revert DemoDao__InvalidVotingPeriod();
        }
        if (_quorumPercentage == 0 || _quorumPercentage > 10000) {
            revert DemoDao__InvalidQuorum();
        }

        GOVERNANCE_TOKEN = IERC20(_governanceToken);
        PROPOSAL_MANAGER = IProposalManager(_proposalManager);
        MIN_TOKENS_TO_PROPOSE = _minTokensToPropose;
        MIN_TOKENS_TO_VOTE = _minTokensToVote;
        VOTING_PERIOD = _votingPeriod;
        QUORUM_PERCENTAGE = _quorumPercentage;
    }

    // ============ External Functions ============

    function createProposal(address target, bytes calldata data, uint256 value, bytes32 membershipRoot)
        external
        returns (uint256 proposalId)
    {
        if (GOVERNANCE_TOKEN.balanceOf(msg.sender) < MIN_TOKENS_TO_PROPOSE) {
            revert DemoDao__InsufficientTokenBalance();
        }

        s_proposalCount++;
        proposalId = s_proposalCount;

        // Create the configuration on the ProposalManager.
        // We use a ballot size of 3 mapping to 0: against, 1: for, 2: abstain.
        PROPOSAL_MANAGER.propose(proposalId, 3, uint64(VOTING_PERIOD), false, membershipRoot);

        s_proposals[proposalId] = ProposalCore({
            proposer: msg.sender,
            target: target,
            value: value,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            status: ProposalStatus.Active,
            executed: false
        });

        s_proposalData[proposalId] = data;

        emit ProposalCreated(proposalId, msg.sender, target, block.timestamp, block.timestamp + VOTING_PERIOD);
    }

    function vote(uint256 proposalId, bytes32 nullifierHash, bytes calldata zkProof, bytes calldata voteData)
        external
        proposalExists(proposalId)
    {
        ProposalCore storage proposal = s_proposals[proposalId];

        if (proposal.status != ProposalStatus.Active) {
            revert DemoDao__ProposalNotActive();
        }

        if (block.timestamp > proposal.endTime) {
            revert DemoDao__VotingPeriodEnded();
        }

        PROPOSAL_MANAGER.submitEncryptedVote(proposalId, nullifierHash, zkProof, voteData);

        // Note: voterWeight is conceptually 1 as handled initially in ProposalManager.
        uint256 voterWeight = 1;
        voterWeight;

        // TODO: emit the decrypted vote choice once the encrypted vote payload is tied to a public support value.
    }

    function execute(uint256 proposalId) external nonReentrant proposalExists(proposalId) {
        ProposalCore storage proposal = s_proposals[proposalId];

        if (proposal.executed) {
            revert DemoDao__ProposalAlreadyExecuted();
        }

        if (block.timestamp <= proposal.endTime) {
            revert DemoDao__ProposalStillActive();
        }

        if (proposal.status == ProposalStatus.Active) {
            _finalizeProposal(proposalId);
        }

        if (proposal.status != ProposalStatus.Passed) {
            revert DemoDao__ProposalNotPassed();
        }

        proposal.executed = true;
        proposal.status = ProposalStatus.Executed;

        bytes memory data = s_proposalData[proposalId];
        (bool success, ) = proposal.target.call{value: proposal.value}(data);

        if (!success) {
            revert DemoDao__ExecutionFailed();
        }

        emit ProposalExecuted(proposalId, success);
    }

    function closeProposal(uint256 proposalId) external proposalExists(proposalId) {
        ProposalCore storage proposal = s_proposals[proposalId];

        if (proposal.status != ProposalStatus.Active) {
            revert DemoDao__ProposalNotActive();
        }

        if (block.timestamp <= proposal.endTime) {
            revert DemoDao__ProposalStillActive();
        }

        _finalizeProposal(proposalId);

        emit ProposalClosed(proposalId, proposal.status);
    }

    // ============ View Functions ============

    function getProposalCount() external view returns (uint256) {
        return s_proposalCount;
    }

    function hasReachedQuorum(uint256 proposalId) public view returns (bool) {
        // Since IProposalManager intentionally reverts if queried before voting ends,
        // this method can only be correctly utilized after the proposal's voting period has concluded.
        uint[] memory counts = PROPOSAL_MANAGER.getProposalById(proposalId).voteCounts;

        // Accumulating total votes across 0 (Against), 1 (For), and 2 (Abstain).
        uint256 totalVotes = counts[0] + counts[1] + counts[2];

        return totalVotes >= (QUORUM_PERCENTAGE * 10);
    }

    function isMember(address account) external view returns (bool) {
        return GOVERNANCE_TOKEN.balanceOf(account) >= MIN_TOKENS_TO_VOTE;
    }

    // ============ Internal Functions ============

    function _checkMember() internal view {
        if (GOVERNANCE_TOKEN.balanceOf(msg.sender) < MIN_TOKENS_TO_VOTE) {
            revert DemoDao__NotAMember();
        }
    }

    function _checkProposalExists(uint256 proposalId) internal view {
        if (proposalId == 0 || proposalId > s_proposalCount) {
            revert DemoDao__ProposalDoesNotExist();
        }
    }

    function _finalizeProposal(uint256 proposalId) internal {
        ProposalCore storage proposal = s_proposals[proposalId];

        bool quorumReached = hasReachedQuorum(proposalId);
        uint[] memory counts = PROPOSAL_MANAGER.getProposalById(proposalId).voteCounts;

        bool passed = quorumReached && counts[1] > counts[0];

        if (passed) {
            proposal.status = ProposalStatus.Passed;
        } else {
            proposal.status = ProposalStatus.Failed;
        }
    }

    receive() external payable {}
}
