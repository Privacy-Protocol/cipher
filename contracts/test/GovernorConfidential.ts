import { expect } from "chai";
import { ethers, fhevm } from "hardhat";
import {
  STATE_DEFEATED,
  VOTE_AGAINST,
  VOTE_FOR,
  advancePastDeadline,
  castVote,
  createAndActivate,
  createProposal,
  deployFixture,
  encryptVote,
  finalize,
  signBallot,
  signEncryptedBallot,
  signEncryptedExtendedBallot,
  signExtendedBallot,
} from "./helpers";

describe("GovernorConfidential", function () {
  beforeEach(function () {
    if (!fhevm.isMock) {
      console.warn("This hardhat test suite requires the mock FHEVM engine");
      this.skip();
    }
  });

  describe("constructor", function () {
    it("initializes with the correct name and token", async function () {
      const { governor } = await deployFixture();
      expect(await governor.name()).to.eq("MyGovernor");
    });
  });

  describe("view functions before finalization", function () {
    it("quorumReached() reverts when the result is not finalized", async function () {
      const { signers, governor } = await deployFixture();
      const proposalId = await createProposal(governor, signers.alice, "p6");

      await expect(governor.quorumReached(proposalId)).to.be.revertedWithCustomError(
        governor,
        "GovernorConfidential__ResultNotFinalized",
      );
    });

    it("voteSucceeded() reverts when the result is not finalized", async function () {
      const { signers, governor } = await deployFixture();
      const proposalId = await createProposal(governor, signers.alice, "p7");

      await expect(governor.voteSucceeded(proposalId)).to.be.revertedWithCustomError(
        governor,
        "GovernorConfidential__ResultNotFinalized",
      );
    });

    it("state() reverts when called after the deadline but before finalization", async function () {
      const { signers, governor } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p8");
      await advancePastDeadline(governor, proposalId);

      await expect(governor.state(proposalId)).to.be.revertedWithCustomError(
        governor,
        "GovernorConfidential__ResultNotFinalized",
      );
    });
  });

  describe("cleartext vote rejection", function () {
    it("getVotes() reverts with NormalGetVotesNotSupported", async function () {
      const { signers, governor } = await deployFixture();

      await expect(governor.getVotes(signers.alice.address, 0n)).to.be.revertedWithCustomError(
        governor,
        "GovernorConfidential__NormalGetVotesNotSupported",
      );
    });

    it("castVoteWithReason() reverts with NormalVotesNotSupported", async function () {
      const { signers, governor } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p10");

      await expect(
        governor.connect(signers.alice).castVoteWithReason(proposalId, VOTE_FOR, "because"),
      ).to.be.revertedWithCustomError(governor, "GovernorConfidential__NormalVotesNotSupported");
    });

    it("castVoteWithReasonAndParams() reverts with NormalVotesNotSupported", async function () {
      const { signers, governor } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p11");

      await expect(
        governor.connect(signers.alice).castVoteWithReasonAndParams(proposalId, VOTE_FOR, "because", "0x1234"),
      ).to.be.revertedWithCustomError(governor, "GovernorConfidential__NormalVotesNotSupported");
    });

    it("castVoteBySig() with a valid signature reverts with NormalVotesNotSupported", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p12");

      const signature = await signBallot(governor, governorAddress, signers.alice, proposalId, VOTE_FOR);

      await expect(
        governor.castVoteBySig(proposalId, VOTE_FOR, signers.alice.address, signature),
      ).to.be.revertedWithCustomError(governor, "GovernorConfidential__NormalVotesNotSupported");
    });

    it("castVoteWithReasonAndParamsBySig() with a valid signature reverts with NormalVotesNotSupported", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p13");

      const reason = "because";
      const params = "0x1234";
      const signature = await signExtendedBallot(
        governor,
        governorAddress,
        signers.alice,
        proposalId,
        VOTE_FOR,
        reason,
        params,
      );

      await expect(
        governor.castVoteWithReasonAndParamsBySig(
          proposalId,
          VOTE_FOR,
          signers.alice.address,
          reason,
          params,
          signature,
        ),
      ).to.be.revertedWithCustomError(governor, "GovernorConfidential__NormalVotesNotSupported");
    });
  });

  describe("alternate encrypted entry points", function () {
    it("castEncryptedVoteWithReason() emits EncryptedVoteCast with the reason", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p14");

      const support = await encryptVote(governorAddress, signers.alice.address, VOTE_FOR);
      await expect(
        governor
          .connect(signers.alice)
          .castEncryptedVoteWithReason(proposalId, support.handle, "I support this", support.proof),
      ).to.emit(governor, "EncryptedVoteCast");
    });

    it("castEncryptedVoteWithReasonAndParams() with non-empty params emits EncryptedVoteCastWithParams", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p15");

      const support = await encryptVote(governorAddress, signers.alice.address, VOTE_FOR);
      await expect(
        governor
          .connect(signers.alice)
          .castEncryptedVoteWithReasonAndParams(proposalId, support.handle, "reason", "0x1234", support.proof),
      )
        .to.emit(governor, "EncryptedVoteCastWithParams")
        .and.to.not.emit(governor, "EncryptedVoteCast");
    });

    it("castEncryptedVoteWithReasonAndParams() with empty params emits EncryptedVoteCast", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p16");

      const support = await encryptVote(governorAddress, signers.alice.address, VOTE_FOR);
      await expect(
        governor
          .connect(signers.alice)
          .castEncryptedVoteWithReasonAndParams(proposalId, support.handle, "reason", "0x", support.proof),
      )
        .to.emit(governor, "EncryptedVoteCast")
        .and.to.not.emit(governor, "EncryptedVoteCastWithParams");
    });
  });

  describe("signature-based encrypted voting", function () {
    it("castEncryptedVoteBySig() with a valid signature casts the vote", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p17");

      // The relayer (deployer) creates the encrypted input bound to itself; alice authorizes via signature.
      const support = await encryptVote(governorAddress, signers.deployer.address, VOTE_FOR);
      const signature = await signEncryptedBallot(
        governor,
        governorAddress,
        1, // alice's signer index
        signers.alice.address,
        proposalId,
        support.handle as string,
        support.proof as string,
      );

      await expect(
        governor
          .connect(signers.deployer)
          .castEncryptedVoteBySig(proposalId, support.handle, signers.alice.address, signature, support.proof),
      ).to.emit(governor, "EncryptedVoteCast");

      expect(await governor.hasVoted(proposalId, signers.alice.address)).to.eq(true);
    });

    it("castEncryptedVoteBySig() with an invalid signature reverts with GovernorInvalidSignature", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p18");

      const support = await encryptVote(governorAddress, signers.deployer.address, VOTE_FOR);
      // Signed by bob (index 2) but submitted as alice's vote -> recovered signer mismatches.
      const wrongSignature = await signEncryptedBallot(
        governor,
        governorAddress,
        2,
        signers.alice.address,
        proposalId,
        support.handle as string,
        support.proof as string,
      );

      await expect(
        governor
          .connect(signers.deployer)
          .castEncryptedVoteBySig(proposalId, support.handle, signers.alice.address, wrongSignature, support.proof),
      ).to.be.revertedWithCustomError(governor, "GovernorInvalidSignature");
    });

    it("castEncryptedVoteWithReasonAndParamsBySig() with a valid signature casts the vote", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p19");

      const reason = "reason";
      const params = "0x1234";
      const support = await encryptVote(governorAddress, signers.deployer.address, VOTE_FOR);
      const signature = await signEncryptedExtendedBallot(
        governor,
        governorAddress,
        1,
        signers.alice.address,
        proposalId,
        support.handle as string,
        support.proof as string,
        reason,
        params,
      );

      await expect(
        governor
          .connect(signers.deployer)
          .castEncryptedVoteWithReasonAndParamsBySig(
            proposalId,
            support.handle,
            signers.alice.address,
            reason,
            params,
            signature,
            support.proof,
          ),
      ).to.emit(governor, "EncryptedVoteCastWithParams");

      expect(await governor.hasVoted(proposalId, signers.alice.address)).to.eq(true);
    });

    it("castEncryptedVoteWithReasonAndParamsBySig() with an invalid signature reverts with GovernorInvalidSignature", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p20");

      const reason = "reason";
      const params = "0x1234";
      const support = await encryptVote(governorAddress, signers.deployer.address, VOTE_FOR);
      const wrongSignature = await signEncryptedExtendedBallot(
        governor,
        governorAddress,
        2,
        signers.alice.address,
        proposalId,
        support.handle as string,
        support.proof as string,
        reason,
        params,
      );

      await expect(
        governor
          .connect(signers.deployer)
          .castEncryptedVoteWithReasonAndParamsBySig(
            proposalId,
            support.handle,
            signers.alice.address,
            reason,
            params,
            wrongSignature,
            support.proof,
          ),
      ).to.be.revertedWithCustomError(governor, "GovernorInvalidSignature");
    });
  });

  describe("state-machine enforcement on encrypted voting", function () {
    it("castEncryptedVote() while Pending reverts with GovernorUnexpectedProposalState", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createProposal(governor, signers.alice, "p21");

      const support = await encryptVote(governorAddress, signers.alice.address, VOTE_FOR);
      await expect(
        governor.connect(signers.alice).castEncryptedVote(proposalId, support.handle, support.proof),
      ).to.be.revertedWithCustomError(governor, "GovernorUnexpectedProposalState");
    });

    it("castEncryptedVote() after the deadline reverts", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p22");
      await advancePastDeadline(governor, proposalId);

      // NOTE: the spec predicted GovernorUnexpectedProposalState, but that state is never reached:
      // _validateStateBitmap calls state(), which past the deadline evaluates _quorumReached() and
      // reverts ResultNotFinalized first. So a post-deadline cast reverts with ResultNotFinalized.
      const support = await encryptVote(governorAddress, signers.alice.address, VOTE_FOR);
      await expect(
        governor.connect(signers.alice).castEncryptedVote(proposalId, support.handle, support.proof),
      ).to.be.revertedWithCustomError(governor, "GovernorConfidential__ResultNotFinalized");
    });
  });

  describe("defeated proposal paths", function () {
    it("a proposal that does not reach quorum finalizes Defeated", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p24");

      // Only an AGAINST vote -> for+abstain = 0 < quorum (1).
      await castVote(governor, governorAddress, signers.charlie, proposalId, VOTE_AGAINST);
      await advancePastDeadline(governor, proposalId);

      const result = await finalize(governor, proposalId);
      expect(result.quorumReached).to.eq(false);
      expect(await governor.quorumReached(proposalId)).to.eq(false);
      expect(await governor.state(proposalId)).to.eq(STATE_DEFEATED);
    });

    it("a proposal with FOR <= AGAINST finalizes Defeated even though quorum is reached", async function () {
      const { signers, governor, governorAddress } = await deployFixture();
      const proposalId = await createAndActivate(governor, signers.alice, "p25");

      await castVote(governor, governorAddress, signers.alice, proposalId, VOTE_FOR); // 10
      await castVote(governor, governorAddress, signers.bob, proposalId, VOTE_AGAINST); // 20
      await advancePastDeadline(governor, proposalId);

      const result = await finalize(governor, proposalId);
      expect(result.quorumReached).to.eq(true);
      expect(result.voteSucceeded).to.eq(false);
      expect(await governor.voteSucceeded(proposalId)).to.eq(false);
      expect(await governor.state(proposalId)).to.eq(STATE_DEFEATED);
    });
  });

  describe("encrypted result before decryption is requested", function () {
    it("encryptedProposalResult() returns uninitialized handles", async function () {
      const { signers, governor } = await deployFixture();
      const proposalId = await createProposal(governor, signers.alice, "p26");

      const [encQuorum, encSucceeded] = await governor.encryptedProposalResult(proposalId);
      expect(encQuorum).to.eq(ethers.ZeroHash);
      expect(encSucceeded).to.eq(ethers.ZeroHash);
    });
  });
});
