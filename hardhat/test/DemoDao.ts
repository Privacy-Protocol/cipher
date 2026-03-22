import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, fhevm } from "hardhat";
import {
  DemoDao,
  DemoDao__factory,
  ProposalManager,
  ProposalManager__factory,
  MockERC20,
  MockERC20__factory,
} from "../types";
import { expect } from "chai";
import { FhevmType } from "@fhevm/hardhat-plugin";
import { time } from "@nomicfoundation/hardhat-network-helpers";

type Signers = {
  deployer: HardhatEthersSigner;
  alice: HardhatEthersSigner;
  bob: HardhatEthersSigner;
  charlie: HardhatEthersSigner;
  nonMember: HardhatEthersSigner;
};

// ─────────── Constants ───────────
const MIN_TOKENS_TO_PROPOSE = ethers.parseEther("100");
const MIN_TOKENS_TO_VOTE = ethers.parseEther("10");
const VOTING_PERIOD = 86400; // 1 day
const QUORUM_PERCENTAGE = 100; // out of 10_000

/**
 * Deploy ProposalManager, MockERC20, and DemoDao.
 * Mints governance tokens to alice, bob, charlie so they qualify as members.
 */
async function deployFixture(signers: Signers) {
  // Deploy ProposalManager
  const pmFactory = (await ethers.getContractFactory("ProposalManager")) as ProposalManager__factory;
  const proposalManager = (await pmFactory.deploy()) as ProposalManager;
  const proposalManagerAddress = await proposalManager.getAddress();

  // Deploy MockERC20
  const tokenFactory = (await ethers.getContractFactory("MockERC20")) as MockERC20__factory;
  const token = (await tokenFactory.deploy("Governance", "GOV")) as MockERC20;
  const tokenAddress = await token.getAddress();

  // Deploy DemoDao
  const daoFactory = (await ethers.getContractFactory("DemoDao")) as DemoDao__factory;
  const dao = (await daoFactory.deploy(
    tokenAddress,
    proposalManagerAddress,
    MIN_TOKENS_TO_PROPOSE,
    MIN_TOKENS_TO_VOTE,
    VOTING_PERIOD,
    QUORUM_PERCENTAGE,
  )) as DemoDao;
  const daoAddress = await dao.getAddress();

  // Mint tokens: alice & bob get enough to propose, charlie just enough to vote
  await token.mint(signers.alice.address, ethers.parseEther("200"));
  await token.mint(signers.bob.address, ethers.parseEther("150"));
  await token.mint(signers.charlie.address, ethers.parseEther("50"));
  // nonMember gets nothing

  return { proposalManager, proposalManagerAddress, token, tokenAddress, dao, daoAddress };
}

/**
 * Helper: encrypts a uint8 vote and ABI-encodes it as (bytes32, bytes) voteData.
 * NOTE: The encrypted input must be created against ProposalManager (the contract
 * where FHE.fromExternal is called), with DemoDao as the signer address (msg.sender
 * inside ProposalManager.submitEncryptedVote is the DemoDao contract address).
 */
async function encryptVote(
  contractAddress: string,
  signerAddress: string,
  voteOption: number,
): Promise<string> {
  const encrypted = await fhevm
    .createEncryptedInput(contractAddress, signerAddress)
    .add8(voteOption)
    .encrypt();

  return ethers.AbiCoder.defaultAbiCoder().encode(
    ["bytes32", "bytes"],
    [encrypted.handles[0], encrypted.inputProof],
  );
}

describe("DemoDao", function () {
  let signers: Signers;
  let proposalManager: ProposalManager;
  let proposalManagerAddress: string;
  let token: MockERC20;
  let dao: DemoDao;
  let daoAddress: string;

  before(async function () {
    const ethSigners = await ethers.getSigners();
    signers = {
      deployer: ethSigners[0],
      alice: ethSigners[1],
      bob: ethSigners[2],
      charlie: ethSigners[3],
      nonMember: ethSigners[4],
    };
  });

  beforeEach(async function () {
    if (!fhevm.isMock) {
      console.warn("This hardhat test suite cannot run on Sepolia Testnet");
      this.skip();
    }

    ({ proposalManager, proposalManagerAddress, token, dao, daoAddress } = await deployFixture(signers));
  });

  // ─────────────────────── Constructor ───────────────────────

  describe("constructor", function () {
    it("should set immutables correctly", async function () {
      expect(await dao.GOVERNANCE_TOKEN()).to.eq(await token.getAddress());
      expect(await dao.PROPOSAL_MANAGER()).to.eq(proposalManagerAddress);
      expect(await dao.MIN_TOKENS_TO_PROPOSE()).to.eq(MIN_TOKENS_TO_PROPOSE);
      expect(await dao.MIN_TOKENS_TO_VOTE()).to.eq(MIN_TOKENS_TO_VOTE);
      expect(await dao.VOTING_PERIOD()).to.eq(VOTING_PERIOD);
      expect(await dao.QUORUM_PERCENTAGE()).to.eq(QUORUM_PERCENTAGE);
    });

    it("should revert if governance token is address(0)", async function () {
      const factory = (await ethers.getContractFactory("DemoDao")) as DemoDao__factory;
      await expect(
        factory.deploy(ethers.ZeroAddress, proposalManagerAddress, MIN_TOKENS_TO_PROPOSE, MIN_TOKENS_TO_VOTE, VOTING_PERIOD, QUORUM_PERCENTAGE),
      ).to.be.revertedWithCustomError(dao, "DemoDao__AddressZero");
    });

    it("should revert if proposalManager is address(0)", async function () {
      const factory = (await ethers.getContractFactory("DemoDao")) as DemoDao__factory;
      await expect(
        factory.deploy(await token.getAddress(), ethers.ZeroAddress, MIN_TOKENS_TO_PROPOSE, MIN_TOKENS_TO_VOTE, VOTING_PERIOD, QUORUM_PERCENTAGE),
      ).to.be.revertedWithCustomError(dao, "DemoDao__AddressZero");
    });

    it("should revert if voting period is 0", async function () {
      const factory = (await ethers.getContractFactory("DemoDao")) as DemoDao__factory;
      await expect(
        factory.deploy(await token.getAddress(), proposalManagerAddress, MIN_TOKENS_TO_PROPOSE, MIN_TOKENS_TO_VOTE, 0, QUORUM_PERCENTAGE),
      ).to.be.revertedWithCustomError(dao, "DemoDao__InvalidVotingPeriod");
    });

    it("should revert if quorum is 0", async function () {
      const factory = (await ethers.getContractFactory("DemoDao")) as DemoDao__factory;
      await expect(
        factory.deploy(await token.getAddress(), proposalManagerAddress, MIN_TOKENS_TO_PROPOSE, MIN_TOKENS_TO_VOTE, VOTING_PERIOD, 0),
      ).to.be.revertedWithCustomError(dao, "DemoDao__InvalidQuorum");
    });

    it("should revert if quorum > 10000", async function () {
      const factory = (await ethers.getContractFactory("DemoDao")) as DemoDao__factory;
      await expect(
        factory.deploy(await token.getAddress(), proposalManagerAddress, MIN_TOKENS_TO_PROPOSE, MIN_TOKENS_TO_VOTE, VOTING_PERIOD, 10001),
      ).to.be.revertedWithCustomError(dao, "DemoDao__InvalidQuorum");
    });
  });

  // ─────────────────── createProposal() ───────────────────

  describe("createProposal", function () {
    it("should create a proposal and increment count", async function () {
      expect(await dao.getProposalCount()).to.eq(0);

      const target = signers.bob.address;
      const data = "0x";
      const value = 0;

      const tx = await dao.connect(signers.alice).createProposal(target, data, value);
      await tx.wait();

      expect(await dao.getProposalCount()).to.eq(1);
    });

    it("should emit ProposalCreated event", async function () {
      const target = signers.bob.address;
      await expect(dao.connect(signers.alice).createProposal(target, "0x", 0))
        .to.emit(dao, "ProposalCreated");
    });

    it("should store correct proposal data", async function () {
      const target = signers.bob.address;
      await dao.connect(signers.alice).createProposal(target, "0x1234", 100);

      const [proposer, storedTarget, storedValue, startTime, endTime, status, executed] =
        await dao.s_proposals(1);

      expect(proposer).to.eq(signers.alice.address);
      expect(storedTarget).to.eq(target);
      expect(storedValue).to.eq(100);
      expect(endTime - startTime).to.eq(VOTING_PERIOD);
      expect(status).to.eq(0); // Active
      expect(executed).to.eq(false);
    });

    it("should also create proposal on ProposalManager", async function () {
      await dao.connect(signers.alice).createProposal(signers.bob.address, "0x", 0);

      // proposalId 1 should exist on ProposalManager with ballotSize = 3
      const pmProposal = await proposalManager.getProposalById(1);
      expect(pmProposal.exists).to.be.true;
      expect(pmProposal.ballotSize).to.eq(3);
    });

    it("should revert if caller has insufficient tokens to propose", async function () {
      // charlie has 50 tokens, needs 100 to propose
      await expect(
        dao.connect(signers.charlie).createProposal(signers.alice.address, "0x", 0),
      ).to.be.revertedWithCustomError(dao, "DemoDao__InsufficientTokenBalance");
    });

    it("should revert if caller has zero tokens", async function () {
      await expect(
        dao.connect(signers.nonMember).createProposal(signers.alice.address, "0x", 0),
      ).to.be.revertedWithCustomError(dao, "DemoDao__InsufficientTokenBalance");
    });
  });

  // ──────────────────────── vote() ────────────────────────

  describe("vote", function () {
    beforeEach(async function () {
      // Alice creates a proposal
      await dao.connect(signers.alice).createProposal(signers.bob.address, "0x", 0);
    });

    it("should allow a member to vote on a proposal", async function () {
      const voteData = await encryptVote(proposalManagerAddress, daoAddress, 1);
      const tx = await dao.connect(signers.alice).vote(1, voteData);
      await tx.wait();

      expect(await dao.hasVoted(1, signers.alice.address)).to.be.true;
    });

    it("should relay the encrypted vote to ProposalManager", async function () {
      const voteData = await encryptVote(proposalManagerAddress, daoAddress, 1);
      await dao.connect(signers.bob).vote(1, voteData);

      // Verify: ProposalManager should have marked the voter (bob) as voted
      expect(await proposalManager.hasVoted(1, signers.bob.address)).to.be.true;
    });

    it("should allow multiple members to vote on the same proposal", async function () {
      const voteDataAlice = await encryptVote(proposalManagerAddress, daoAddress, 1);
      await dao.connect(signers.alice).vote(1, voteDataAlice);

      const voteDataBob = await encryptVote(proposalManagerAddress, daoAddress, 0);
      await dao.connect(signers.bob).vote(1, voteDataBob);

      expect(await dao.hasVoted(1, signers.alice.address)).to.be.true;
      expect(await dao.hasVoted(1, signers.bob.address)).to.be.true;
    });

    it("should produce correct encrypted tallies after votes", async function () {
      // Alice votes For (option 1)
      const voteDataAlice = await encryptVote(proposalManagerAddress, daoAddress, 1);
      await dao.connect(signers.alice).vote(1, voteDataAlice);

      // Bob votes For (option 1)
      const voteDataBob = await encryptVote(proposalManagerAddress, daoAddress, 1);
      await dao.connect(signers.bob).vote(1, voteDataBob);

      // Charlie votes Against (option 0)
      const voteDataCharlie = await encryptVote(proposalManagerAddress, daoAddress, 0);
      await dao.connect(signers.charlie).vote(1, voteDataCharlie);

      // Verify tallies via debugger
      const clearTally0 = await fhevm.debugger.decryptEuint(
        FhevmType.euint64,
        await proposalManager.encryptedTallies(1, 0),
      );
      const clearTally1 = await fhevm.debugger.decryptEuint(
        FhevmType.euint64,
        await proposalManager.encryptedTallies(1, 1),
      );
      const clearTally2 = await fhevm.debugger.decryptEuint(
        FhevmType.euint64,
        await proposalManager.encryptedTallies(1, 2),
      );

      expect(clearTally0).to.eq(1n); // 1 Against
      expect(clearTally1).to.eq(2n); // 2 For
      expect(clearTally2).to.eq(0n); // 0 Abstain
    });

    it("should revert if non-member tries to vote", async function () {
      const voteData = await encryptVote(proposalManagerAddress, daoAddress, 1);
      await expect(
        dao.connect(signers.nonMember).vote(1, voteData),
      ).to.be.revertedWithCustomError(dao, "DemoDao__NotAMember");
    });

    it("should revert if member votes twice", async function () {
      const voteData1 = await encryptVote(proposalManagerAddress, daoAddress, 1);
      await dao.connect(signers.alice).vote(1, voteData1);

      const voteData2 = await encryptVote(proposalManagerAddress, daoAddress, 0);
      await expect(
        dao.connect(signers.alice).vote(1, voteData2),
      ).to.be.revertedWithCustomError(dao, "DemoDao__AlreadyVoted");
    });

    it("should revert if proposal does not exist", async function () {
      const voteData = await encryptVote(proposalManagerAddress, daoAddress, 1);
      await expect(
        dao.connect(signers.alice).vote(999, voteData),
      ).to.be.revertedWithCustomError(dao, "DemoDao__ProposalDoesNotExist");
    });

    it("should revert if voting period has ended", async function () {
      await time.increase(VOTING_PERIOD + 1);

      const voteData = await encryptVote(proposalManagerAddress, daoAddress, 1);
      await expect(
        dao.connect(signers.alice).vote(1, voteData),
      ).to.be.revertedWithCustomError(dao, "DemoDao__VotingPeriodEnded");
    });
  });

  // ────────────── closeProposal() ──────────────

  describe("closeProposal", function () {
    beforeEach(async function () {
      await dao.connect(signers.alice).createProposal(signers.bob.address, "0x", 0);
    });

    it("should revert if voting period has not ended", async function () {
      await expect(dao.closeProposal(1)).to.be.revertedWithCustomError(dao, "DemoDao__ProposalStillActive");
    });

    it("should revert if proposal does not exist", async function () {
      await expect(dao.closeProposal(999)).to.be.revertedWithCustomError(dao, "DemoDao__ProposalDoesNotExist");
    });
  });

  // ──────────── View functions ────────────

  describe("View functions", function () {
    it("isMember should return true for token holders", async function () {
      expect(await dao.isMember(signers.alice.address)).to.be.true;
      expect(await dao.isMember(signers.charlie.address)).to.be.true;
    });

    it("isMember should return false for non-holders", async function () {
      expect(await dao.isMember(signers.nonMember.address)).to.be.false;
    });

    it("hasVoted should return false before voting", async function () {
      await dao.connect(signers.alice).createProposal(signers.bob.address, "0x", 0);
      expect(await dao.hasVoted(1, signers.alice.address)).to.be.false;
    });

    it("getProposalCount should track proposal count", async function () {
      expect(await dao.getProposalCount()).to.eq(0);
      await dao.connect(signers.alice).createProposal(signers.bob.address, "0x", 0);
      expect(await dao.getProposalCount()).to.eq(1);
      await dao.connect(signers.bob).createProposal(signers.alice.address, "0x", 0);
      expect(await dao.getProposalCount()).to.eq(2);
    });
  });
});
