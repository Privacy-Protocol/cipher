import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, fhevm } from "hardhat";
import { HonkVerifier, HonkVerifier__factory, ProposalManager, ProposalManager__factory } from "../types";
import { expect } from "chai";
import { FhevmType } from "@fhevm/hardhat-plugin";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { generateVoteSubmissionProof } from "../scripts/generateVoteSubmissionProof";
import { buildMembershipTree } from "../scripts/proofUtils";

type Signers = {
  deployer: HardhatEthersSigner;
  alice: HardhatEthersSigner;
  bob: HardhatEthersSigner;
  charlie: HardhatEthersSigner;
};

const DEFAULT_MEMBERSHIP_ROOT = ethers.keccak256(ethers.toUtf8Bytes("demo-membership-root"));
const TEST_MEMBER_IDENTITY_SECRETS = [1001n, 1002n, 1003n];
const MEMBER_INDEX_BY_SIGNER = {
  alice: 0,
  bob: 1,
  charlie: 2,
} as const;

async function deployVoteSubmissionVerifier() {
  const zkTranscriptLibFactory = await ethers.getContractFactory("ZKTranscriptLib");
  const zkTranscriptLib = await zkTranscriptLibFactory.deploy();
  const zkTranscriptLibAddress = await zkTranscriptLib.getAddress();

  const verifierFactory = (await ethers.getContractFactory("HonkVerifier", {
    libraries: {
      ZKTranscriptLib: zkTranscriptLibAddress,
    },
  })) as HonkVerifier__factory;

  const voteSubmissionVerifier = (await verifierFactory.deploy()) as HonkVerifier;
  const voteSubmissionVerifierAddress = await voteSubmissionVerifier.getAddress();

  return { voteSubmissionVerifier, voteSubmissionVerifierAddress };
}

async function deployFixture() {
  const { voteSubmissionVerifier, voteSubmissionVerifierAddress } = await deployVoteSubmissionVerifier();

  const factory = (await ethers.getContractFactory("ProposalManager")) as ProposalManager__factory;
  const proposalManagerContract = (await factory.deploy(voteSubmissionVerifierAddress)) as ProposalManager;
  const proposalManagerAddress = await proposalManagerContract.getAddress();

  return { proposalManagerContract, proposalManagerAddress, voteSubmissionVerifier, voteSubmissionVerifierAddress };
}

/**
 * Helper: encrypts a uint8 vote and ABI-encodes it as (bytes32, bytes) voteData
 */
async function encryptVote(
  proposalManagerAddress: string,
  signer: HardhatEthersSigner,
  voteOption: number
): Promise<string> {
  const encrypted = await fhevm
    .createEncryptedInput(proposalManagerAddress, signer.address)
    .add8(voteOption)
    .encrypt();

  return ethers.AbiCoder.defaultAbiCoder().encode(
    ["bytes32", "bytes"],
    [encrypted.handles[0], encrypted.inputProof]
  );
}

function buildNullifier(proposalId: number, signer: HardhatEthersSigner): string {
  return ethers.keccak256(
    ethers.solidityPacked(["uint256", "address"], [proposalId, signer.address])
  );
}

describe("ProposalManager", function () {
  let signers: Signers;
  let proposalManagerContract: ProposalManager;
  let proposalManagerAddress: string;
  let realMembershipRoot: string;

  before(async function () {
    const ethSigners: HardhatEthersSigner[] = await ethers.getSigners();
    signers = {
      deployer: ethSigners[0],
      alice: ethSigners[1],
      bob: ethSigners[2],
      charlie: ethSigners[3],
    };

    const membershipTree = await buildMembershipTree(TEST_MEMBER_IDENTITY_SECRETS);
    realMembershipRoot = ethers.zeroPadValue(ethers.toBeHex(membershipTree.membershipRoot), 32);
  });

  beforeEach(async function () {
    if (!fhevm.isMock) {
      console.warn(`This hardhat test suite cannot run on Sepolia Testnet`);
      this.skip();
    }

    ({ proposalManagerContract, proposalManagerAddress } = await deployFixture());
  });

  // ───────────────────────── propose() ─────────────────────────

  describe("propose", function () {
    it("should create a proposal with correct config", async function () {
      const proposalId = 1;
      const ballotSize = 3;
      const votingPeriod = 86400;

      const tx = await proposalManagerContract.propose(
        proposalId,
        ballotSize,
        votingPeriod,
        false,
        DEFAULT_MEMBERSHIP_ROOT
      );
      await tx.wait();

      const proposal = await proposalManagerContract.getProposalById(proposalId);
      expect(proposal.exists).to.be.true;
      expect(proposal.ballotSize).to.eq(ballotSize);
      expect(proposal.allowLiveReveal).to.eq(false);
      expect(proposal.membershipRoot).to.eq(DEFAULT_MEMBERSHIP_ROOT);
      expect(proposal.votingEnd).to.be.greaterThan(proposal.votingStart);
    });

    it("should revert if proposal already exists", async function () {
      await proposalManagerContract.propose(1, 2, 86400, false, DEFAULT_MEMBERSHIP_ROOT);
      await expect(
        proposalManagerContract.propose(1, 2, 86400, false, DEFAULT_MEMBERSHIP_ROOT)
      ).to.be.revertedWithCustomError(
        proposalManagerContract,
        "ProposalManager__ProposalAlreadyExists"
      );
    });

    it("should revert if ballotSize is 0", async function () {
      await expect(
        proposalManagerContract.propose(1, 0, 86400, false, DEFAULT_MEMBERSHIP_ROOT)
      ).to.be.revertedWithCustomError(
        proposalManagerContract,
        "ProposalManager__InvalidBallotSize"
      );
    });

    it("should revert if ballotSize > 16", async function () {
      await expect(
        proposalManagerContract.propose(1, 17, 86400, false, DEFAULT_MEMBERSHIP_ROOT)
      ).to.be.revertedWithCustomError(
        proposalManagerContract,
        "ProposalManager__InvalidBallotSize"
      );
    });

    it("should revert if votingPeriod is 0", async function () {
      await expect(
        proposalManagerContract.propose(1, 3, 0, false, DEFAULT_MEMBERSHIP_ROOT)
      ).to.be.revertedWithCustomError(
        proposalManagerContract,
        "ProposalManager__InvalidVotingPeriod"
      );
    });

    it("should revert if membershipRoot is zero", async function () {
      await expect(
        proposalManagerContract.propose(1, 3, 86400, false, ethers.ZeroHash)
      ).to.be.revertedWithCustomError(proposalManagerContract, "ProposalManager__InvalidMembershipRoot");
    });

    it("should emit ProposalCreated event", async function () {
      await expect(
        proposalManagerContract.propose(1, 3, 86400, false, DEFAULT_MEMBERSHIP_ROOT)
      )
        .to.emit(proposalManagerContract, "ProposalCreated")
        .withArgs(1, 3, 86400);
    });
  });

  // ─────────────────── submitEncryptedVote() ───────────────────

  describe("submitEncryptedVote", function () {
    const proposalId = 1;
    const ballotSize = 3;
    const votingPeriod = 86400;

    async function buildVoteProof(
      signerKey: keyof typeof MEMBER_INDEX_BY_SIGNER,
      vote: number,
      overrideProposalId = proposalId
    ) {
      return generateVoteSubmissionProof({
        proposalId: overrideProposalId,
        ballotSize,
        vote,
        memberIdentitySecrets: TEST_MEMBER_IDENTITY_SECRETS,
        voterIndex: MEMBER_INDEX_BY_SIGNER[signerKey],
      });
    }

    beforeEach(async function () {
      await proposalManagerContract.propose(
        proposalId,
        ballotSize,
        votingPeriod,
        false,
        realMembershipRoot
      );
    });

    it("should accept an encrypted vote and emit VoteSubmitted", async function () {
      const voteProof = await buildVoteProof("alice", 1);
      const voteData = await encryptVote(proposalManagerAddress, signers.alice, 1);

      expect(voteProof.publicInputs).to.deep.equal([
        ethers.zeroPadValue(ethers.toBeHex(proposalId), 32),
        realMembershipRoot,
        ethers.zeroPadValue(ethers.toBeHex(ballotSize), 32),
        voteProof.nullifierHash,
      ]);

      await expect(
        proposalManagerContract
          .connect(signers.alice)
          .submitEncryptedVote(proposalId, voteProof.nullifierHash, voteProof.proof, voteData)
      ).to.emit(proposalManagerContract, "VoteSubmitted").withArgs(proposalId);
    });

    it("should mark the nullifier as used", async function () {
      const voteProof = await buildVoteProof("alice", 0);
      const voteData = await encryptVote(proposalManagerAddress, signers.alice, 0);
      await proposalManagerContract
        .connect(signers.alice)
        .submitEncryptedVote(proposalId, voteProof.nullifierHash, voteProof.proof, voteData);

      expect(await proposalManagerContract.nullifierUsed(proposalId, voteProof.nullifierHash)).to.be.true;
    });

    it("should revert if a nullifier is reused", async function () {
      const voteProof = await buildVoteProof("alice", 0);
      const voteData = await encryptVote(proposalManagerAddress, signers.alice, 0);
      await proposalManagerContract
        .connect(signers.alice)
        .submitEncryptedVote(proposalId, voteProof.nullifierHash, voteProof.proof, voteData);

      const voteData2 = await encryptVote(proposalManagerAddress, signers.alice, 1);
      await expect(
        proposalManagerContract
          .connect(signers.alice)
          .submitEncryptedVote(proposalId, voteProof.nullifierHash, voteProof.proof, voteData2)
      ).to.be.revertedWithCustomError(proposalManagerContract, "ProposalManager__NullifierAlreadyUsed");
    });

    it("should revert if the ZK proof payload is empty", async function () {
      const voteProof = await buildVoteProof("alice", 0);
      const voteData = await encryptVote(proposalManagerAddress, signers.alice, 0);

      await expect(
        proposalManagerContract
          .connect(signers.alice)
          .submitEncryptedVote(proposalId, voteProof.nullifierHash, "0x", voteData)
      ).to.be.reverted;
    });

    it("should revert if proposal does not exist", async function () {
      const voteProof = await buildVoteProof("alice", 0, 999);
      const voteData = await encryptVote(proposalManagerAddress, signers.alice, 0);
      await expect(
        proposalManagerContract
          .connect(signers.alice)
          .submitEncryptedVote(999, voteProof.nullifierHash, voteProof.proof, voteData)
      ).to.be.revertedWithCustomError(proposalManagerContract, "ProposalManager__ProposalNotExists");
    });

    it("should revert if voting period has ended", async function () {
      await time.increase(votingPeriod + 1);

      const voteProof = await buildVoteProof("alice", 0);
      const voteData = await encryptVote(proposalManagerAddress, signers.alice, 0);
      await expect(
        proposalManagerContract
          .connect(signers.alice)
          .submitEncryptedVote(proposalId, voteProof.nullifierHash, voteProof.proof, voteData)
      ).to.be.revertedWithCustomError(proposalManagerContract, "ProposalManager__VotingPeriodEnded");
    });
  });

  // ─────────────────────── endVoting() ─────────────────────────

  describe("endVoting", function () {
    const proposalId = 1;
    const ballotSize = 3; // For, Against, Abstain
    const votingPeriod = 86400;
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(["uint64[]"], [[0, 0, 0]]);

    beforeEach(async function () {
      await proposalManagerContract.propose(
        proposalId,
        ballotSize,
        votingPeriod,
        false,
        DEFAULT_MEMBERSHIP_ROOT
      );
    });

    it("should revert if voting period has not ended", async function () {
      await expect(
        proposalManagerContract.endVoting(proposalId, encoded, "0x")
      ).to.be.revertedWithCustomError(proposalManagerContract, "ProposalManager__VotingPeriodNotEnded");
    });

    it("should revert if proposal does not exist", async function () {
      await time.increase(votingPeriod + 1);
      await expect(
        proposalManagerContract.endVoting(999, encoded, "0x")
      ).to.be.revertedWithCustomError(proposalManagerContract, "ProposalManager__ProposalNotExists");
    });

    it("should revert if the decryption proof payload is empty after voting ends", async function () {
      await time.increase(votingPeriod + 1);

      await expect(proposalManagerContract.endVoting(proposalId, encoded, "0x")).to.be.reverted;
    });
  });

  // ────────── Encrypted Tally Verification (via debugger) ──────────

  describe("Encrypted tally correctness", function () {
    const proposalId = 1;
    const ballotSize = 3;
    const votingPeriod = 86400;

    beforeEach(async function () {
      await proposalManagerContract.propose(
        proposalId,
        ballotSize,
        votingPeriod,
        false,
        realMembershipRoot
      );
    });

    it("should produce correct encrypted tallies after multiple votes", async function () {
      // Alice votes option 1 (For)
      const aliceVoteProof = await generateVoteSubmissionProof({
        proposalId,
        ballotSize,
        vote: 1,
        memberIdentitySecrets: TEST_MEMBER_IDENTITY_SECRETS,
        voterIndex: MEMBER_INDEX_BY_SIGNER.alice,
      });
      const voteDataAlice = await encryptVote(proposalManagerAddress, signers.alice, 1);
      await proposalManagerContract
        .connect(signers.alice)
        .submitEncryptedVote(proposalId, aliceVoteProof.nullifierHash, aliceVoteProof.proof, voteDataAlice);

      // Bob votes option 1 (For)
      const bobVoteProof = await generateVoteSubmissionProof({
        proposalId,
        ballotSize,
        vote: 1,
        memberIdentitySecrets: TEST_MEMBER_IDENTITY_SECRETS,
        voterIndex: MEMBER_INDEX_BY_SIGNER.bob,
      });
      const voteDataBob = await encryptVote(proposalManagerAddress, signers.bob, 1);
      await proposalManagerContract
        .connect(signers.bob)
        .submitEncryptedVote(proposalId, bobVoteProof.nullifierHash, bobVoteProof.proof, voteDataBob);

      // Charlie votes option 0 (Against)
      const charlieVoteProof = await generateVoteSubmissionProof({
        proposalId,
        ballotSize,
        vote: 0,
        memberIdentitySecrets: TEST_MEMBER_IDENTITY_SECRETS,
        voterIndex: MEMBER_INDEX_BY_SIGNER.charlie,
      });
      const voteDataCharlie = await encryptVote(proposalManagerAddress, signers.charlie, 0);
      await proposalManagerContract
        .connect(signers.charlie)
        .submitEncryptedVote(
          proposalId,
          charlieVoteProof.nullifierHash,
          charlieVoteProof.proof,
          voteDataCharlie
        );

      // Decrypt the encrypted tallies directly via the FHEVM debugger
      const clearTally0 = await fhevm.debugger.decryptEuint(
        FhevmType.euint64,
        await proposalManagerContract.encryptedTallies(proposalId, 0)
      );
      const clearTally1 = await fhevm.debugger.decryptEuint(
        FhevmType.euint64,
        await proposalManagerContract.encryptedTallies(proposalId, 1)
      );
      const clearTally2 = await fhevm.debugger.decryptEuint(
        FhevmType.euint64,
        await proposalManagerContract.encryptedTallies(proposalId, 2)
      );

      // Option 0 (Against): 1 vote (Charlie)
      expect(clearTally0).to.eq(1n);
      // Option 1 (For): 2 votes (Alice + Bob)
      expect(clearTally1).to.eq(2n);
      // Option 2 (Abstain): 0 votes
      expect(clearTally2).to.eq(0n);
    });

    it("should correctly tally a single vote", async function () {
      const voteProof = await generateVoteSubmissionProof({
        proposalId,
        ballotSize,
        vote: 2,
        memberIdentitySecrets: TEST_MEMBER_IDENTITY_SECRETS,
        voterIndex: MEMBER_INDEX_BY_SIGNER.alice,
      });
      const voteData = await encryptVote(proposalManagerAddress, signers.alice, 2);
      await proposalManagerContract
        .connect(signers.alice)
        .submitEncryptedVote(proposalId, voteProof.nullifierHash, voteProof.proof, voteData);

      const clearTally0 = await fhevm.debugger.decryptEuint(
        FhevmType.euint64,
        await proposalManagerContract.encryptedTallies(proposalId, 0)
      );
      const clearTally1 = await fhevm.debugger.decryptEuint(
        FhevmType.euint64,
        await proposalManagerContract.encryptedTallies(proposalId, 1)
      );
      const clearTally2 = await fhevm.debugger.decryptEuint(
        FhevmType.euint64,
        await proposalManagerContract.encryptedTallies(proposalId, 2)
      );

      expect(clearTally0).to.eq(0n);
      expect(clearTally1).to.eq(0n);
      expect(clearTally2).to.eq(1n);
    });
  });

  // ──────────────────── getProposalById() ──────────────────────

  describe("getProposalById", function () {
    it("should revert if proposal does not exist", async function () {
      await expect(proposalManagerContract.getProposalById(999)).to.be.revertedWithCustomError(
        proposalManagerContract,
        "ProposalManager__ProposalNotExists"
      );
    });

    it("should return correct proposal config", async function () {
      await proposalManagerContract.propose(5, 2, 3600, true, DEFAULT_MEMBERSHIP_ROOT);
      const proposal = await proposalManagerContract.getProposalById(5);

      expect(proposal.ballotSize).to.eq(2);
      expect(proposal.allowLiveReveal).to.be.true;
      expect(proposal.exists).to.be.true;
      expect(proposal.membershipRoot).to.eq(DEFAULT_MEMBERSHIP_ROOT);
    });
  });
});
