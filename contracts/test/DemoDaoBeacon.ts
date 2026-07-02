import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { FhevmType } from "@fhevm/hardhat-plugin";
import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import {
  buildMembershipTree,
  MEMBERSHIP_ID as SDK_MEMBERSHIP_ID,
  proveMembershipFromSecrets,
  toBytes32,
  type MembershipProof,
} from "@privacy-protocol/beacon";

import {
  CircuitRegistry,
  DemoDao,
  HonkVerifier__factory,
  MembershipHubAdapter,
  MyToken,
  VerifierHub,
} from "../types";

// Cross-product integration test (Cipher × Beacon): the DemoDao verifies membership proofs through
// Beacon's VerifierHub instead of an embedded verifier. The DAO is wired to a MembershipHubAdapter
// (an IVerifier shim) that forwards verify(proof, publicInputs) -> hub.verify(MEMBERSHIP_ID, ...).
// Proofs (and the membership root) are produced by the published @privacy-protocol/beacon SDK — the
// same client path a real consumer uses — so this test dogfoods the SDK end to end.

// BN254 scalar field — Governor proposalIds (keccak hashes) are reduced into this field before
// being passed to the membership circuit (scope = proposalId mod p).
const SNARK_SCALAR_FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

// Beacon membership catalog circuit (must match the deployed registry entry + SDK MEMBERSHIP_ID).
const MEMBERSHIP_VK_HASH = "0x0f4c997743e86ee7eecd61d6a2d4307c817a7ecaccd75686b48ca4e1bdcab0cc";
const MEMBERSHIP_ID = "0x05559ff444cd5e85ff9633527685ac1e6009465c3ee0635569270e76d2c9597b";

const VOTE_AGAINST = 0;
const VOTE_FOR = 1;

const STATE_ACTIVE = 1n;
const STATE_SUCCEEDED = 4n;

const IDENTITY_SECRETS = [1001n, 1002n, 1003n];
const MEMBER_INDEX = { alice: 0, bob: 1, charlie: 2 } as const;
const TOKEN_WEIGHTS = { alice: 10n, bob: 20n, charlie: 5n } as const;

type Signers = {
  deployer: HardhatEthersSigner;
  alice: HardhatEthersSigner;
  bob: HardhatEthersSigner;
  charlie: HardhatEthersSigner;
};

async function encryptUint64(contractAddress: string, signerAddress: string, value: bigint) {
  const encrypted = await fhevm.createEncryptedInput(contractAddress, signerAddress).add64(value).encrypt();
  return { handle: encrypted.handles[0], proof: encrypted.inputProof };
}

async function encryptVote(contractAddress: string, signerAddress: string, support: number) {
  const encrypted = await fhevm.createEncryptedInput(contractAddress, signerAddress).add8(support).encrypt();
  return { handle: encrypted.handles[0], proof: encrypted.inputProof };
}

async function deployVerifier(): Promise<string> {
  const zkTranscriptLib = await (await ethers.getContractFactory("ZKTranscriptLib")).deploy();
  const verifierFactory = (await ethers.getContractFactory("HonkVerifier", {
    libraries: { ZKTranscriptLib: await zkTranscriptLib.getAddress() },
  })) as HonkVerifier__factory;
  const verifier = await verifierFactory.deploy();
  return verifier.getAddress();
}

describe("DemoDao × Beacon hub", function () {
  let signers: Signers;
  let token: MyToken;
  let tokenAddress: string;
  let registry: CircuitRegistry;
  let hub: VerifierHub;
  let shim: MembershipHubAdapter;
  let dao: DemoDao;
  let daoAddress: string;
  let membershipRoot: string;

  let targets: string[];
  let values: bigint[];
  let calldatas: string[];
  const description = "DemoDao × Beacon: fund the membership-gated initiative";

  const proofCache = new Map<number, MembershipProof>();

  // Dogfood the published SDK: generate the membership proof exactly as a real consumer would.
  async function membershipProofFor(voterIndex: number, proposalId: bigint): Promise<MembershipProof> {
    const cached = proofCache.get(voterIndex);
    if (cached) return cached;
    const proof = await proveMembershipFromSecrets({
      scope: proposalId % SNARK_SCALAR_FIELD,
      secrets: IDENTITY_SECRETS,
      voterIndex,
    });
    proofCache.set(voterIndex, proof);
    return proof;
  }

  async function castMembershipVote(voter: HardhatEthersSigner, voterIndex: number, proposalId: bigint, support: number) {
    const proof = await membershipProofFor(voterIndex, proposalId);
    const encrypted = await encryptVote(daoAddress, voter.address, support);
    return dao
      .connect(voter)
      .castEncryptedVoteWithMembershipProof(proposalId, encrypted.handle, encrypted.proof, proof.nullifier, proof.proof);
  }

  before(async function () {
    const eth = await ethers.getSigners();
    signers = { deployer: eth[0], alice: eth[1], bob: eth[2], charlie: eth[3] };

    // Membership root via the SDK — the same Poseidon2 tree a consumer builds off-chain.
    const tree = await buildMembershipTree(IDENTITY_SECRETS);
    membershipRoot = toBytes32(tree.root);

    targets = [signers.deployer.address];
    values = [0n];
    calldatas = ["0x"];
  });

  beforeEach(async function () {
    if (!fhevm.isMock) {
      console.warn("This hardhat test suite requires the mock FHEVM engine");
      this.skip();
    }

    // --- Stand up Beacon: registry + hub + (reused) verifier, then register the membership circuit.
    const verifierAddress = await deployVerifier();

    registry = (await (await ethers.getContractFactory("CircuitRegistry")).deploy(
      signers.deployer.address,
    )) as unknown as CircuitRegistry;

    hub = (await (await ethers.getContractFactory("VerifierHub")).deploy(
      await registry.getAddress(),
    )) as unknown as VerifierHub;

    // The content-addressed id is independent of the verifier; assert it matches the SDK constant.
    expect(await registry.circuitId("membership", 1)).to.eq(MEMBERSHIP_ID);
    await registry.registerCircuit(
      "membership",
      1,
      verifierAddress,
      MEMBERSHIP_VK_HASH,
      3,
      "scope,root,nullifier",
    );

    // --- The shim the DAO consumes: pins MEMBERSHIP_ID, forwards verify to the hub.
    shim = (await (await ethers.getContractFactory("MembershipHubAdapter")).deploy(
      await hub.getAddress(),
      MEMBERSHIP_ID,
    )) as unknown as MembershipHubAdapter;

    token = (await (await ethers.getContractFactory("MyToken")).deploy(
      signers.deployer.address,
      signers.deployer.address,
    )) as unknown as MyToken;
    tokenAddress = await token.getAddress();

    // --- The DAO points its voteSubmissionVerifier at the Beacon shim instead of a bare verifier.
    dao = (await (await ethers.getContractFactory("DemoDao")).deploy(
      tokenAddress,
      await shim.getAddress(),
      membershipRoot,
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
    const proposalId = await dao.hashProposal(targets, values, calldatas, ethers.id(description));
    await dao.connect(signers.alice).propose(targets, values, calldatas, description);
    await time.increaseTo((await dao.proposalSnapshot(proposalId)) + 1n);
    return proposalId;
  }

  it("wires the DAO to verify through the Beacon shim and hub", async function () {
    // Dogfood cross-check: the SDK's MEMBERSHIP_ID is the id wired on-chain.
    expect(SDK_MEMBERSHIP_ID).to.eq(MEMBERSHIP_ID);
    expect(await dao.zkMembershipEnabled()).to.eq(true);
    expect(await dao.voteSubmissionVerifier()).to.eq(await shim.getAddress());
    expect(await shim.hub()).to.eq(await hub.getAddress());
    expect(await shim.circuitId()).to.eq(MEMBERSHIP_ID);
    expect(await hub.registry()).to.eq(await registry.getAddress());
  });

  it("runs the full membership-gated flow through Beacon: propose, prove + vote, tally, finalize", async function () {
    const proposalId = await propose();
    expect(await dao.state(proposalId)).to.eq(STATE_ACTIVE);

    await expect(castMembershipVote(signers.alice, MEMBER_INDEX.alice, proposalId, VOTE_FOR)).to.emit(
      dao,
      "EncryptedVoteCast",
    );
    await castMembershipVote(signers.bob, MEMBER_INDEX.bob, proposalId, VOTE_FOR);
    await castMembershipVote(signers.charlie, MEMBER_INDEX.charlie, proposalId, VOTE_AGAINST);

    for (const name of ["alice", "bob", "charlie"] as const) {
      const proof = proofCache.get(MEMBER_INDEX[name])!;
      expect(await dao.nullifierUsed(proposalId, proof.nullifier)).to.eq(true);
    }

    // Token-weighted tally: alice(10) + bob(20) FOR, charlie(5) AGAINST.
    const [against, forVotes, abstain] = await dao.proposalVotes(proposalId);
    expect(await fhevm.debugger.decryptEuint(FhevmType.euint64, against)).to.eq(5n);
    expect(await fhevm.debugger.decryptEuint(FhevmType.euint64, forVotes)).to.eq(30n);
    expect(await fhevm.debugger.decryptEuint(FhevmType.euint64, abstain)).to.eq(0n);

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

  it("proves the hub is really in the verification path: deactivating the circuit blocks voting", async function () {
    const proposalId = await propose();

    // Flip the catalog entry inactive — the hub now rejects, so an otherwise-valid proof fails.
    await registry.connect(signers.deployer).setCircuitActive(MEMBERSHIP_ID, false);

    const proof = await membershipProofFor(MEMBER_INDEX.alice, proposalId);
    const support = await encryptVote(daoAddress, signers.alice.address, VOTE_FOR);
    await expect(
      dao
        .connect(signers.alice)
        .castEncryptedVoteWithMembershipProof(proposalId, support.handle, support.proof, proof.nullifier, proof.proof),
    ).to.be.revertedWithCustomError(hub, "VerifierHub__InactiveCircuit");
  });

  it("rejects a membership proof generated for a different proposal", async function () {
    const proposalId = await propose();

    const wrongProof = await proveMembershipFromSecrets({
      scope: (proposalId % SNARK_SCALAR_FIELD) + 1n,
      secrets: IDENTITY_SECRETS,
      voterIndex: MEMBER_INDEX.alice,
    });
    const support = await encryptVote(daoAddress, signers.alice.address, VOTE_FOR);
    await expect(
      dao
        .connect(signers.alice)
        .castEncryptedVoteWithMembershipProof(proposalId, support.handle, support.proof, wrongProof.nullifier, wrongProof.proof),
    ).to.be.reverted;
  });
});
