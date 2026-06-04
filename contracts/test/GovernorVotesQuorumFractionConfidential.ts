import { FhevmType } from "@fhevm/hardhat-plugin";
import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import { MyGovernor, MyToken } from "../types";
import {
  Signers,
  VOTE_FOR,
  activate,
  advancePastDeadline,
  castVote,
  createProposal,
  deployFixture,
  encryptUint64,
  finalize,
} from "./helpers";

/**
 * Runs a governor self-call proposal to completion (propose -> vote -> finalize -> Succeeded) and returns
 * a thunk that performs `execute()`. The executor of a no-timelock Governor is the governor itself, so an
 * onlyGovernance function can only be reached this way.
 */
async function prepareGovernanceCall(
  governor: MyGovernor,
  governorAddress: string,
  signers: Signers,
  calldata: string,
  description: string,
) {
  const targets = [governorAddress];
  const values = [0n];
  const calldatas = [calldata];
  const descriptionHash = ethers.id(description);
  const proposalId = await governor.hashProposal(targets, values, calldatas, descriptionHash);

  await governor.connect(signers.alice).propose(targets, values, calldatas, description);
  await activate(governor, proposalId);
  await castVote(governor, governorAddress, signers.alice, proposalId, VOTE_FOR); // 10 -> quorum + succeeds
  await advancePastDeadline(governor, proposalId);
  await finalize(governor, proposalId);

  return () => governor.execute(targets, values, calldatas, descriptionHash);
}

function updateNumeratorData(governor: MyGovernor, newNumerator: bigint) {
  return governor.interface.encodeFunctionData("updateQuorumNumerator", [newNumerator]);
}

/**
 * Decrypts confidentialQuorum at `timepoint`. confidentialQuorum is non-view, so its FHE result is only
 * persisted (and thus decryptable) after a real transaction; the handle itself is deterministic, so we
 * run the tx to persist, then read the same handle via staticCall.
 */
async function decryptConfidentialQuorum(governor: MyGovernor, timepoint: bigint) {
  await (await governor.confidentialQuorum(timepoint)).wait();
  const handle = await governor.confidentialQuorum.staticCall(timepoint);
  return fhevm.debugger.decryptEuint(FhevmType.euint64, handle);
}

describe("GovernorVotesQuorumFractionConfidential", function () {
  beforeEach(function () {
    if (!fhevm.isMock) {
      console.warn("This hardhat test suite requires the mock FHEVM engine");
      this.skip();
    }
  });

  describe("constructor validation", function () {
    it("deploying with a numerator > 100 reverts with GovernorInvalidQuorumFraction", async function () {
      const { tokenAddress } = await deployFixture();
      const factory = await ethers.getContractFactory("ConfigurableGovernor");
      const reference = await factory.deploy(tokenAddress, 4n); // valid, used for the error interface

      await expect(factory.deploy(tokenAddress, 101n)).to.be.revertedWithCustomError(
        reference,
        "GovernorInvalidQuorumFraction",
      );
    });
  });

  describe("view accessors", function () {
    it("quorumDenominator() returns 100", async function () {
      const { governor } = await deployFixture();
      expect(await governor.quorumDenominator()).to.eq(100n);
    });

    it("quorumNumerator() returns the most recently set numerator", async function () {
      const { governor } = await deployFixture();
      expect(await governor.quorumNumerator()).to.eq(4n);
    });

    it("quorum(timepoint) reverts with GovernorConfidentialQuorumIsEncrypted", async function () {
      const { governor } = await deployFixture();
      await expect(governor.quorum(0n)).to.be.revertedWithCustomError(
        governor,
        "GovernorConfidentialQuorumIsEncrypted",
      );
    });
  });

  describe("confidentialQuorum", function () {
    it("confidentialQuorum(timepoint) decrypts to floor(totalSupply * numerator / 100)", async function () {
      const { governor, token } = await deployFixture();
      const timepoint = (await token.clock()) - 1n;

      // total supply 35, numerator 4 -> floor(35 * 4 / 100) = 1
      expect(await decryptConfidentialQuorum(governor, timepoint)).to.eq(1n);
    });

    it("confidentialQuorum with zero total supply decrypts to zero", async function () {
      const [deployer, alice] = await ethers.getSigners();
      const token = (await (
        await ethers.getContractFactory("MyToken")
      ).deploy(deployer.address, deployer.address)) as unknown as MyToken;
      const tokenAddress = await token.getAddress();
      // Mint 0 so the total-supply handle is initialized but the supply stays zero.
      const enc0 = await encryptUint64(tokenAddress, deployer.address, 0n);
      await token.connect(deployer).mint(alice.address, enc0.handle, enc0.proof);

      const governor = (await (
        await ethers.getContractFactory("MyGovernor")
      ).deploy(tokenAddress)) as unknown as MyGovernor;
      const governorAddress = await governor.getAddress();
      await token.connect(deployer).getHandleAllowance(await token.confidentialTotalSupply(), governorAddress, true);

      const timepoint = (await token.clock()) - 1n;
      expect(await decryptConfidentialQuorum(governor, timepoint)).to.eq(0n);
    });
  });

  describe("updateQuorumNumerator (governance-gated)", function () {
    it("a non-governance caller reverts with GovernorOnlyExecutor", async function () {
      const { signers, governor } = await deployFixture();
      await expect(governor.connect(signers.alice).updateQuorumNumerator(5n)).to.be.revertedWithCustomError(
        governor,
        "GovernorOnlyExecutor",
      );
    });

    it("through governance emits QuorumNumeratorUpdated(old, new)", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const execute = await prepareGovernanceCall(
        governor,
        governorAddress,
        signers,
        updateNumeratorData(governor, 10n),
        "update to 10",
      );

      await expect(execute()).to.emit(governor, "QuorumNumeratorUpdated").withArgs(4n, 10n);
      expect(await governor.quorumNumerator()).to.eq(10n);
    });

    it("through governance with a value > 100 reverts with GovernorInvalidQuorumFraction", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const execute = await prepareGovernanceCall(
        governor,
        governorAddress,
        signers,
        updateNumeratorData(governor, 101n),
        "update to 101",
      );

      await expect(execute()).to.be.revertedWithCustomError(governor, "GovernorInvalidQuorumFraction");
    });

    it("a zero numerator is accepted and proposals always reach quorum", async function () {
      const { signers, governor, governorAddress } = await deployFixture(undefined, 0n);
      expect(await governor.quorumNumerator()).to.eq(0n);

      const proposalId = await createProposal(governor, signers.alice, "zero-quorum");
      await activate(governor, proposalId);
      // Only a tiny against vote: for + abstain = 0, but quorum is 0 so it is still reached.
      await castVote(governor, governorAddress, signers.charlie, proposalId, VOTE_FOR); // 5
      await advancePastDeadline(governor, proposalId);

      const result = await finalize(governor, proposalId);
      expect(result.quorumReached).to.eq(true);
    });

    it("a numerator of 100 is accepted", async function () {
      const { governor } = await deployFixture(undefined, 100n);
      expect(await governor.quorumNumerator()).to.eq(100n);
    });
  });

  describe("historical numerator lookup", function () {
    it("quorumNumerator(timepoint) after the latest update returns the latest numerator", async function () {
      const { governor } = await deployFixture();
      const future = (await governor.clock()) + 1000n;
      expect(await governor["quorumNumerator(uint256)"](future)).to.eq(4n);
    });

    it("quorumNumerator(timepoint) before the latest update returns the older numerator", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const beforeUpdate = await governor.clock();

      const execute = await prepareGovernanceCall(
        governor,
        governorAddress,
        signers,
        updateNumeratorData(governor, 10n),
        "update to 10",
      );
      await execute();

      expect(await governor.quorumNumerator()).to.eq(10n); // latest
      expect(await governor["quorumNumerator(uint256)"](beforeUpdate)).to.eq(4n); // historical (binary search)
    });

    it("a proposal evaluates quorum with the numerator at its snapshot, not a later value", async function () {
      const { signers, governor, governorAddress } = await deployFixture();

      // Proposal created while the numerator is 4.
      const proposalId = await createProposal(governor, signers.alice, "snapshot-numerator");
      const snapshot = await governor.proposalSnapshot(proposalId);

      // Numerator later bumped to 10 via a separate governance proposal.
      const execute = await prepareGovernanceCall(
        governor,
        governorAddress,
        signers,
        updateNumeratorData(governor, 10n),
        "bump to 10",
      );
      await execute();
      expect(await governor.quorumNumerator()).to.eq(10n);

      // Quorum at the original snapshot still uses numerator 4: floor(35 * 4 / 100) = 1 (not 35*10/100 = 3).
      expect(await decryptConfidentialQuorum(governor, snapshot)).to.eq(1n);
    });
  });
});
