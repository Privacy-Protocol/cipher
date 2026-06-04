import { FhevmType } from "@fhevm/hardhat-plugin";
import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import { MyGovernor } from "../types";
import { VOTE_FOR, castVote, createAndActivate, deployFixture } from "./helpers";

describe("GovernorVotesConfidential", function () {
  beforeEach(function () {
    if (!fhevm.isMock) {
      console.warn("This hardhat test suite requires the mock FHEVM engine");
      this.skip();
    }
  });

  it("token() returns the address the governor was deployed with", async function () {
    const { governor, tokenAddress } = await deployFixture();
    expect(await governor.token()).to.eq(tokenAddress);
  });

  it("clock() delegates to the token's clock()", async function () {
    const { governor, token } = await deployFixture();
    expect(await governor.clock()).to.eq(await token.clock());
  });

  it("CLOCK_MODE() delegates to the token's CLOCK_MODE()", async function () {
    const { governor, token } = await deployFixture();
    expect(await governor.CLOCK_MODE()).to.eq(await token.CLOCK_MODE());
    expect(await governor.CLOCK_MODE()).to.eq("mode=timestamp");
  });

  describe("ERC-6372 fallback when the token does not implement a clock", function () {
    async function deployWithNonClockToken() {
      const mockFactory = await ethers.getContractFactory("MockNonClockVotes");
      const mockToken = await mockFactory.deploy();
      const governorFactory = await ethers.getContractFactory("MyGovernor");
      const governor = (await governorFactory.deploy(await mockToken.getAddress())) as unknown as MyGovernor;
      return { governor };
    }

    it("clock() falls back to the block number", async function () {
      const { governor } = await deployWithNonClockToken();
      expect(await governor.clock()).to.eq(BigInt(await ethers.provider.getBlockNumber()));
    });

    it("CLOCK_MODE() falls back to the default block-number mode string", async function () {
      const { governor } = await deployWithNonClockToken();
      expect(await governor.CLOCK_MODE()).to.eq("mode=blocknumber&from=default");
    });
  });

  it("vote weight is read at the proposal snapshot, not the current block", async function () {
    const { signers, governor, governorAddress, token } = await deployFixture();
    const proposalId = await createAndActivate(governor, signers.alice, "v6");

    // After the snapshot, bob re-delegates his 20 to alice, raising alice's *current* votes to 30.
    await token.connect(signers.bob).delegate(signers.alice.address);

    // Alice votes: only her snapshot weight (10) must be counted, not her current 30.
    await castVote(governor, governorAddress, signers.alice, proposalId, VOTE_FOR);

    const [, forVotes] = await governor.proposalVotes(proposalId);
    expect(await fhevm.debugger.decryptEuint(FhevmType.euint64, forVotes)).to.eq(10n);
  });
});
