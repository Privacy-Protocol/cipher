import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { FhevmType } from "@fhevm/hardhat-plugin";
import { expect } from "chai";
import { ethers, fhevm } from "hardhat";

import { DemoDao, HonkVerifier, HonkVerifier__factory, MyToken } from "../types";
import { generateVoteSubmissionProof, VoteSubmissionProofPayload } from "../scripts/generateVoteSubmissionProof";
import { buildMembershipTree, toBytes32 } from "../scripts/proofUtils";

// BN254 scalar field — Governor proposalIds (keccak hashes) are reduced into this field before
// being passed to the membership circuit, exactly as PrivateDaoAdapter does on-chain.
const SNARK_SCALAR_FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

const VOTE_AGAINST = 0;
const VOTE_FOR = 1;
const VOTE_ABSTAIN = 2;

// Governor proposal states (IGovernor.ProposalState).
const STATE_ACTIVE = 1n;
const STATE_SUCCEEDED = 4n;

// DAO members. Index in this array is the leaf index used by the membership proof.
const IDENTITY_SECRETS = [1001n, 1002n, 1003n];
const MEMBER_INDEX = { alice: 0, bob: 1, charlie: 2 } as const;
// Token voting weights (drives the confidential tally; membership proof only gates eligibility).
const TOKEN_WEIGHTS = { alice: 10n, bob: 20n, charlie: 5n } as const;

type Signers = {
  deployer: HardhatEthersSigner;
  alice: HardhatEthersSigner;
  bob: HardhatEthersSigner;
  charlie: HardhatEthersSigner;
  nonMember: HardhatEthersSigner;
};

async function encryptUint64(contractAddress: string, signerAddress: string, value: bigint) {
  const encrypted = await fhevm.createEncryptedInput(contractAddress, signerAddress).add64(value).encrypt();
  return { handle: encrypted.handles[0], proof: encrypted.inputProof };
}

async function encryptVote(contractAddress: string, signerAddress: string, support: number) {
  const encrypted = await fhevm.createEncryptedInput(contractAddress, signerAddress).add8(support).encrypt();
  return { handle: encrypted.handles[0], proof: encrypted.inputProof };
}

async function deployVerifier(): Promise<{ verifier: HonkVerifier; verifierAddress: string }> {
  const zkTranscriptLib = await (await ethers.getContractFactory("ZKTranscriptLib")).deploy();
  const verifierFactory = (await ethers.getContractFactory("HonkVerifier", {
    libraries: { ZKTranscriptLib: await zkTranscriptLib.getAddress() },
  })) as HonkVerifier__factory;
  const verifier = (await verifierFactory.deploy()) as HonkVerifier;
  return { verifier, verifierAddress: await verifier.getAddress() };
}

describe("DemoDao", function () {
  let signers: Signers;
  let token: MyToken;
  let tokenAddress: string;
  let dao: DemoDao;
  let daoAddress: string;
  let membershipRoot: string;

  // Fixed proposal actions → deterministic proposalId (hashProposal does not depend on the
  // governor address), so membership proofs can be generated once and reused across deployments.
  let targets: string[];
  let values: bigint[];
  let calldatas: string[];
  const description = "DemoDao: fund the membership-gated initiative";

  const proofCache = new Map<number, VoteSubmissionProofPayload>();

  async function membershipProofFor(voterIndex: number, reducedProposalId: bigint): Promise<VoteSubmissionProofPayload> {
    const cached = proofCache.get(voterIndex);
    if (cached) return cached;
    const proof = await generateVoteSubmissionProof({
      proposalId: reducedProposalId,
      memberIdentitySecrets: IDENTITY_SECRETS,
      voterIndex,
    });
    proofCache.set(voterIndex, proof);
    return proof;
  }

  async function castMembershipVote(
    voter: HardhatEthersSigner,
    voterIndex: number,
    proposalId: bigint,
    support: number,
  ) {
    const reduced = proposalId % SNARK_SCALAR_FIELD;
    const proof = await membershipProofFor(voterIndex, reduced);
    const encrypted = await encryptVote(daoAddress, voter.address, support);
    return dao
      .connect(voter)
      .castEncryptedVoteWithMembershipProof(proposalId, encrypted.handle, encrypted.proof, proof.nullifierHash, proof.proof);
  }

  before(async function () {
    const eth = await ethers.getSigners();
    signers = { deployer: eth[0], alice: eth[1], bob: eth[2], charlie: eth[3], nonMember: eth[4] };

    const tree = await buildMembershipTree(IDENTITY_SECRETS);
    membershipRoot = toBytes32(tree.membershipRoot);

    targets = [signers.deployer.address];
    values = [0n];
    calldatas = ["0x"];
  });

  beforeEach(async function () {
    if (!fhevm.isMock) {
      console.warn("This hardhat test suite requires the mock FHEVM engine");
      this.skip();
    }

    const { verifierAddress } = await deployVerifier();

    token = (await (await ethers.getContractFactory("MyToken")).deploy(
      signers.deployer.address,
      signers.deployer.address,
    )) as unknown as MyToken;
    tokenAddress = await token.getAddress();

    dao = (await (await ethers.getContractFactory("DemoDao")).deploy(
      tokenAddress,
      verifierAddress,
      membershipRoot,
    )) as unknown as DemoDao;
    daoAddress = await dao.getAddress();

    // Mint + delegate token voting power, then grant the DAO FHE-handle access to votes & supply.
    for (const name of ["alice", "bob", "charlie"] as const) {
      const holder = signers[name];
      const enc = await encryptUint64(tokenAddress, signers.deployer.address, TOKEN_WEIGHTS[name]);
      await token.connect(signers.deployer).mint(holder.address, enc.handle, enc.proof);
      await token.connect(holder).delegate(holder.address);
    }
    for (const name of ["alice", "bob", "charlie"] as const) {
      await token
        .connect(signers.deployer)
        .getHandleAllowance(await token.getVotes(signers[name].address), daoAddress, true);
    }
    await token.connect(signers.deployer).getHandleAllowance(await token.confidentialTotalSupply(), daoAddress, true);
  });

  async function propose(): Promise<bigint> {
    const proposalId = await dao.hashProposal(targets, values, calldatas, ethers.id(description));
    await dao.connect(signers.alice).propose(targets, values, calldatas, description);
    await time.increaseTo((await dao.proposalSnapshot(proposalId)) + 1n);
    return proposalId;
  }

  it("runs the full membership-gated flow: propose, prove membership + vote, tally, finalize", async function () {
    const proposalId = await propose();
    expect(await dao.state(proposalId)).to.eq(STATE_ACTIVE);

    await expect(castMembershipVote(signers.alice, MEMBER_INDEX.alice, proposalId, VOTE_FOR)).to.emit(
      dao,
      "EncryptedVoteCast",
    );
    await castMembershipVote(signers.bob, MEMBER_INDEX.bob, proposalId, VOTE_FOR);
    await castMembershipVote(signers.charlie, MEMBER_INDEX.charlie, proposalId, VOTE_AGAINST);

    // Each vote is bound to msg.sender, so hasVoted is set per address.
    expect(await dao.hasVoted(proposalId, signers.alice.address)).to.eq(true);
    expect(await dao.hasVoted(proposalId, signers.bob.address)).to.eq(true);
    expect(await dao.hasVoted(proposalId, signers.charlie.address)).to.eq(true);

    // Nullifiers spent for this proposal.
    for (const name of ["alice", "bob", "charlie"] as const) {
      const proof = proofCache.get(MEMBER_INDEX[name])!;
      expect(await dao.nullifierUsed(proposalId, proof.nullifierHash)).to.eq(true);
    }

    // Token-weighted tally: alice(10) + bob(20) FOR, charlie(5) AGAINST.
    const [against, forVotes, abstain] = await dao.proposalVotes(proposalId);
    expect(await fhevm.debugger.decryptEuint(FhevmType.euint64, against)).to.eq(5n);
    expect(await fhevm.debugger.decryptEuint(FhevmType.euint64, forVotes)).to.eq(30n);
    expect(await fhevm.debugger.decryptEuint(FhevmType.euint64, abstain)).to.eq(0n);

    // Finalize after the deadline.
    await time.increaseTo((await dao.proposalDeadline(proposalId)) + 1n);
    await dao.requestProposalResultDecryption(proposalId);
    const [encQuorum, encSucceeded] = await dao.encryptedProposalResult(proposalId);
    const decrypted = await fhevm.publicDecrypt([encQuorum, encSucceeded]);
    await expect(
      dao.finalizeProposalResult(proposalId, decrypted.abiEncodedClearValues, decrypted.decryptionProof),
    ).to.emit(dao, "ProposalResultFinalized");

    expect(await dao.quorumReached(proposalId)).to.eq(true);
    expect(await dao.voteSucceeded(proposalId)).to.eq(true);
    expect(await dao.state(proposalId)).to.eq(STATE_SUCCEEDED);
  });

  it("rejects the un-gated inherited castEncryptedVote entrypoint", async function () {
    const proposalId = await propose();
    const support = await encryptVote(daoAddress, signers.alice.address, VOTE_FOR);

    await expect(
      dao.connect(signers.alice).castEncryptedVote(proposalId, support.handle, support.proof),
    ).to.be.revertedWithCustomError(dao, "PDA__MembershipProofRequired");
  });

  it("rejects a reused nullifier on the same proposal", async function () {
    const proposalId = await propose();
    await castMembershipVote(signers.alice, MEMBER_INDEX.alice, proposalId, VOTE_FOR);

    // Re-submit alice's proof (same nullifier). The nullifier check reverts before re-tallying.
    const proof = proofCache.get(MEMBER_INDEX.alice)!;
    const support = await encryptVote(daoAddress, signers.alice.address, VOTE_AGAINST);
    await expect(
      dao
        .connect(signers.alice)
        .castEncryptedVoteWithMembershipProof(proposalId, support.handle, support.proof, proof.nullifierHash, proof.proof),
    ).to.be.revertedWithCustomError(dao, "PDA__NullifierAlreadyUsed");
  });

  it("rejects a membership proof generated for a different proposal", async function () {
    const proposalId = await propose();

    // Proof bound to a different (reduced) proposalId → public inputs won't match → verify fails.
    const wrongProof = await generateVoteSubmissionProof({
      proposalId: (proposalId % SNARK_SCALAR_FIELD) + 1n,
      memberIdentitySecrets: IDENTITY_SECRETS,
      voterIndex: MEMBER_INDEX.alice,
    });
    const support = await encryptVote(daoAddress, signers.alice.address, VOTE_FOR);

    // The Honk verifier reverts internally on a non-matching proof (e.g. SumcheckFailed), so the
    // vote is rejected; we assert it reverts rather than pinning the exact verifier error.
    await expect(
      dao
        .connect(signers.alice)
        .castEncryptedVoteWithMembershipProof(proposalId, support.handle, support.proof, wrongProof.nullifierHash, wrongProof.proof),
    ).to.be.reverted;
  });
});

describe("DemoDao — optional ZK gate disabled (FHE-only)", function () {
  let signers: Signers;
  let token: MyToken;
  let tokenAddress: string;
  let dao: DemoDao;
  let daoAddress: string;

  const targets = () => [signers.deployer.address];
  const values = [0n];
  const calldatas = ["0x"];
  const description = "DemoDao: FHE-only proposal (no membership gate)";

  beforeEach(async function () {
    if (!fhevm.isMock) {
      console.warn("This hardhat test suite requires the mock FHEVM engine");
      this.skip();
    }

    const eth = await ethers.getSigners();
    signers = { deployer: eth[0], alice: eth[1], bob: eth[2], charlie: eth[3], nonMember: eth[4] };

    token = (await (await ethers.getContractFactory("MyToken")).deploy(
      signers.deployer.address,
      signers.deployer.address,
    )) as unknown as MyToken;
    tokenAddress = await token.getAddress();

    // Deploy the adapter with NO verifier and a zero root → ZK membership gate disabled.
    dao = (await (await ethers.getContractFactory("DemoDao")).deploy(
      tokenAddress,
      ethers.ZeroAddress,
      ethers.ZeroHash,
    )) as unknown as DemoDao;
    daoAddress = await dao.getAddress();

    for (const name of ["alice", "bob", "charlie"] as const) {
      const holder = signers[name];
      const enc = await encryptUint64(tokenAddress, signers.deployer.address, TOKEN_WEIGHTS[name]);
      await token.connect(signers.deployer).mint(holder.address, enc.handle, enc.proof);
      await token.connect(holder).delegate(holder.address);
    }
    for (const name of ["alice", "bob", "charlie"] as const) {
      await token
        .connect(signers.deployer)
        .getHandleAllowance(await token.getVotes(signers[name].address), daoAddress, true);
    }
    await token.connect(signers.deployer).getHandleAllowance(await token.confidentialTotalSupply(), daoAddress, true);
  });

  async function propose(): Promise<bigint> {
    const proposalId = await dao.hashProposal(targets(), values, calldatas, ethers.id(description));
    await dao.connect(signers.alice).propose(targets(), values, calldatas, description);
    await time.increaseTo((await dao.proposalSnapshot(proposalId)) + 1n);
    return proposalId;
  }

  it("reports the ZK gate as disabled with no verifier or root configured", async function () {
    expect(await dao.zkMembershipEnabled()).to.eq(false);
    expect(await dao.voteSubmissionVerifier()).to.eq(ethers.ZeroAddress);
    expect(await dao.membershipRoot()).to.eq(ethers.ZeroHash);
  });

  it("accepts plain encrypted votes via the inherited entrypoint and tallies them", async function () {
    const proposalId = await propose();
    expect(await dao.state(proposalId)).to.eq(STATE_ACTIVE);

    const aliceSupport = await encryptVote(daoAddress, signers.alice.address, VOTE_FOR);
    await expect(
      dao.connect(signers.alice).castEncryptedVote(proposalId, aliceSupport.handle, aliceSupport.proof),
    ).to.emit(dao, "EncryptedVoteCast");

    const bobSupport = await encryptVote(daoAddress, signers.bob.address, VOTE_AGAINST);
    await dao.connect(signers.bob).castEncryptedVote(proposalId, bobSupport.handle, bobSupport.proof);

    // alice(10) FOR, bob(20) AGAINST.
    const [against, forVotes, abstain] = await dao.proposalVotes(proposalId);
    expect(await fhevm.debugger.decryptEuint(FhevmType.euint64, against)).to.eq(20n);
    expect(await fhevm.debugger.decryptEuint(FhevmType.euint64, forVotes)).to.eq(10n);
    expect(await fhevm.debugger.decryptEuint(FhevmType.euint64, abstain)).to.eq(0n);
  });

  it("rejects the membership-proof entrypoint when the ZK gate is disabled", async function () {
    const proposalId = await propose();
    const support = await encryptVote(daoAddress, signers.alice.address, VOTE_FOR);

    await expect(
      dao
        .connect(signers.alice)
        .castEncryptedVoteWithMembershipProof(proposalId, support.handle, support.proof, ethers.ZeroHash, "0x"),
    ).to.be.revertedWithCustomError(dao, "PDA__MembershipProofNotEnabled");
  });

  it("rejects setMembershipRoot when the ZK gate is disabled", async function () {
    const tree = await buildMembershipTree(IDENTITY_SECRETS);
    await expect(
      dao.connect(signers.deployer).setMembershipRoot(toBytes32(tree.membershipRoot)),
    ).to.be.revertedWithCustomError(dao, "PDA__MembershipProofNotEnabled");
  });

  it("reverts deployment when a membership root is supplied without a verifier", async function () {
    const tree = await buildMembershipTree(IDENTITY_SECRETS);
    const factory = await ethers.getContractFactory("DemoDao");
    await expect(
      factory.deploy(tokenAddress, ethers.ZeroAddress, toBytes32(tree.membershipRoot)),
    ).to.be.revertedWithCustomError(factory, "PDA__InvalidMembershipRoot");
  });

  it("lets the owner enable the ZK gate at runtime, then enforces membership proofs", async function () {
    const tree = await buildMembershipTree(IDENTITY_SECRETS);
    const root = toBytes32(tree.membershipRoot);
    const { verifierAddress } = await deployVerifier();

    await expect(dao.connect(signers.deployer).setZkMembership(verifierAddress, root))
      .to.emit(dao, "PDA__ZkMembershipConfigured")
      .withArgs(verifierAddress, root, true);

    expect(await dao.zkMembershipEnabled()).to.eq(true);
    expect(await dao.voteSubmissionVerifier()).to.eq(verifierAddress);
    expect(await dao.membershipRoot()).to.eq(root);

    const proposalId = await propose();

    // The inherited un-gated path is now disabled.
    const ungated = await encryptVote(daoAddress, signers.alice.address, VOTE_FOR);
    await expect(
      dao.connect(signers.alice).castEncryptedVote(proposalId, ungated.handle, ungated.proof),
    ).to.be.revertedWithCustomError(dao, "PDA__MembershipProofRequired");

    // The membership-proof path now works.
    const proof = await generateVoteSubmissionProof({
      proposalId: proposalId % SNARK_SCALAR_FIELD,
      memberIdentitySecrets: IDENTITY_SECRETS,
      voterIndex: MEMBER_INDEX.alice,
    });
    const support = await encryptVote(daoAddress, signers.alice.address, VOTE_FOR);
    await expect(
      dao
        .connect(signers.alice)
        .castEncryptedVoteWithMembershipProof(proposalId, support.handle, support.proof, proof.nullifierHash, proof.proof),
    ).to.emit(dao, "PDA__MembershipVoteCast");
  });

  it("lets the owner disable the ZK gate again at runtime, restoring un-gated voting", async function () {
    const tree = await buildMembershipTree(IDENTITY_SECRETS);
    const { verifierAddress } = await deployVerifier();
    await dao.connect(signers.deployer).setZkMembership(verifierAddress, toBytes32(tree.membershipRoot));
    expect(await dao.zkMembershipEnabled()).to.eq(true);

    await expect(dao.connect(signers.deployer).setZkMembership(ethers.ZeroAddress, ethers.ZeroHash))
      .to.emit(dao, "PDA__ZkMembershipConfigured")
      .withArgs(ethers.ZeroAddress, ethers.ZeroHash, false);
    expect(await dao.zkMembershipEnabled()).to.eq(false);
    expect(await dao.membershipRoot()).to.eq(ethers.ZeroHash);

    const proposalId = await propose();
    const support = await encryptVote(daoAddress, signers.alice.address, VOTE_FOR);
    await expect(
      dao.connect(signers.alice).castEncryptedVote(proposalId, support.handle, support.proof),
    ).to.emit(dao, "EncryptedVoteCast");
  });

  it("restricts setZkMembership to the owner and validates its arguments", async function () {
    const tree = await buildMembershipTree(IDENTITY_SECRETS);
    const root = toBytes32(tree.membershipRoot);
    const { verifierAddress } = await deployVerifier();

    await expect(
      dao.connect(signers.alice).setZkMembership(verifierAddress, root),
    ).to.be.revertedWithCustomError(dao, "OwnableUnauthorizedAccount");

    // Verifier address with no contract code.
    await expect(
      dao.connect(signers.deployer).setZkMembership(signers.alice.address, root),
    ).to.be.revertedWithCustomError(dao, "PDA__InvalidVerifier");

    // Verifier set but zero root.
    await expect(
      dao.connect(signers.deployer).setZkMembership(verifierAddress, ethers.ZeroHash),
    ).to.be.revertedWithCustomError(dao, "PDA__InvalidMembershipRoot");

    // Zero verifier but non-zero root.
    await expect(
      dao.connect(signers.deployer).setZkMembership(ethers.ZeroAddress, root),
    ).to.be.revertedWithCustomError(dao, "PDA__InvalidMembershipRoot");
  });
});
