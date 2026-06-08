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
