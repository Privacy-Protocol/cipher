import { FhevmType } from "@fhevm/hardhat-plugin";
import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import {
  VOTE_ABSTAIN,
  VOTE_AGAINST,
  VOTE_FOR,
  advancePastDeadline,
  castVote,
  createAndActivate,
  createProposal,
  deployFixture,
  finalize,
} from "./helpers";

async function decryptVotes(governor: Awaited<ReturnType<typeof deployFixture>>["governor"], proposalId: bigint) {
  const [against, forVotes, abstain] = await governor.proposalVotes(proposalId);
  return {
    against: await fhevm.debugger.decryptEuint(FhevmType.euint64, against),
    for: await fhevm.debugger.decryptEuint(FhevmType.euint64, forVotes),
    abstain: await fhevm.debugger.decryptEuint(FhevmType.euint64, abstain),
  };
}

describe("GovernorCountingSimpleConfidential", function () {
  beforeEach(function () {
    if (!fhevm.isMock) {
      console.warn("This hardhat test suite requires the mock FHEVM engine");
      this.skip();
    }
  });

  it("COUNTING_MODE() returns the bravo for-and-abstain mode string", async function () {
    const { governor } = await deployFixture();
    expect(await governor.COUNTING_MODE()).to.eq("support=bravo&quorum=for,abstain");
  });

  it("proposalVotes() before any votes returns uninitialized handles", async function () {
    const { signers, governor } = await deployFixture();
    const proposalId = await createProposal(governor, signers.alice, "c2");

    const [against, forVotes, abstain] = await governor.proposalVotes(proposalId);
    expect(against).to.eq(ethers.ZeroHash);
    expect(forVotes).to.eq(ethers.ZeroHash);
    expect(abstain).to.eq(ethers.ZeroHash);
  });

  it("an abstain vote only increments the abstain counter", async function () {
    const { signers, governor, governorAddress } = await deployFixture();
    const proposalId = await createAndActivate(governor, signers.alice, "c3");

    await castVote(governor, governorAddress, signers.alice, proposalId, VOTE_ABSTAIN); // weight 10

    const votes = await decryptVotes(governor, proposalId);
    expect(votes.abstain).to.eq(10n);
    expect(votes.for).to.eq(0n);
    expect(votes.against).to.eq(0n);
  });

  it("quorum counts FOR + ABSTAIN: abstain-only votes can reach quorum", async function () {
    const { signers, governor, governorAddress } = await deployFixture();
    const proposalId = await createAndActivate(governor, signers.alice, "c4");

    await castVote(governor, governorAddress, signers.alice, proposalId, VOTE_ABSTAIN); // 10 >= quorum (1)
    await advancePastDeadline(governor, proposalId);

    const result = await finalize(governor, proposalId);
    expect(result.quorumReached).to.eq(true);
  });

  it("a proposal with AGAINST > FOR finalizes with voteSucceeded == false", async function () {
    const { signers, governor, governorAddress } = await deployFixture();
    const proposalId = await createAndActivate(governor, signers.alice, "c5");

    await castVote(governor, governorAddress, signers.alice, proposalId, VOTE_FOR); // 10
    await castVote(governor, governorAddress, signers.bob, proposalId, VOTE_AGAINST); // 20
    await advancePastDeadline(governor, proposalId);

    const result = await finalize(governor, proposalId);
    expect(result.voteSucceeded).to.eq(false);
  });

  it("a proposal with FOR + ABSTAIN below quorum finalizes with quorumReached == false", async function () {
    const { signers, governor, governorAddress } = await deployFixture();
    const proposalId = await createAndActivate(governor, signers.alice, "c6");

    await castVote(governor, governorAddress, signers.charlie, proposalId, VOTE_AGAINST); // for+abstain = 0
    await advancePastDeadline(governor, proposalId);

    const result = await finalize(governor, proposalId);
    expect(result.quorumReached).to.eq(false);
  });

  it("a tie (FOR == AGAINST) finalizes with voteSucceeded == false", async function () {
    const { signers, governor, governorAddress } = await deployFixture([
      ["alice", 10n],
      ["bob", 10n],
    ]);
    const proposalId = await createAndActivate(governor, signers.alice, "c7");

    await castVote(governor, governorAddress, signers.alice, proposalId, VOTE_FOR); // 10
    await castVote(governor, governorAddress, signers.bob, proposalId, VOTE_AGAINST); // 10
    await advancePastDeadline(governor, proposalId);

    const result = await finalize(governor, proposalId);
    expect(result.voteSucceeded).to.eq(false); // FHE.gt is strict
  });

  it("the first vote initializes the counters and subsequent votes accumulate", async function () {
    const { signers, governor, governorAddress } = await deployFixture();
    const proposalId = await createAndActivate(governor, signers.alice, "c8");

    await castVote(governor, governorAddress, signers.alice, proposalId, VOTE_FOR); // initializes, +10
    await castVote(governor, governorAddress, signers.bob, proposalId, VOTE_FOR); // accumulates, +20

    const votes = await decryptVotes(governor, proposalId);
    expect(votes.for).to.eq(30n);
    expect(votes.against).to.eq(0n);
    expect(votes.abstain).to.eq(0n);
  });
});
