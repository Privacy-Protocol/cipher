import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { buildMembershipTree, toBytes32 } from "../scripts/proofUtils";

// Demo DAO member identity secrets. The membership tree leaf is Poseidon(identity_secret), so a
// "member" is a field-element secret, not an address. The deployed root commits to these; the same
// secrets are needed off-chain to generate vote-submission proofs. Override the root via the
// MEMBERSHIP_ROOT env var (32-byte hex) to deploy against a real member set instead.
//
// For the demo we also seed two members from the addresses below, using each address value directly
// as its identity secret. NOTE: an address is public, so anyone could forge a membership proof for
// these two — demo only; real members must use a privately-held secret.
const DEMO_MEMBER_ADDRESSES = [
  "0x1C945Cd472EFBE3b34798AA49457Bc7415636E5D",
  "0x9ce826910f5e22A6e22A6a0418033b2677505752",
];
const DEMO_IDENTITY_SECRETS = [1001n, 1002n, 1003n, ...DEMO_MEMBER_ADDRESSES.map((address) => BigInt(address))];

async function resolveMembershipRoot(): Promise<string> {
  if (process.env.MEMBERSHIP_ROOT) {
    return process.env.MEMBERSHIP_ROOT;
  }
  const tree = await buildMembershipTree(DEMO_IDENTITY_SECRETS);
  return toBytes32(tree.membershipRoot);
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;
  const { ethers, network } = hre;
  const waitConfirmations = network.name === "sepolia" ? 2 : 1;

  // 1. Confidential votes token (IVotesConfidential) — deployer is admin + handle viewer.
  const deployedToken = await deploy("MyToken", {
    from: deployer,
    args: [deployer, deployer],
    log: true,
    waitConfirmations,
  });

  // 2. Membership-proof verifier. HonkVerifier links the ZKTranscriptLib library.
  const deployedZkLib = await deploy("ZKTranscriptLib", {
    from: deployer,
    log: true,
    waitConfirmations,
  });

  const deployedVerifier = await deploy("HonkVerifier", {
    from: deployer,
    libraries: { ZKTranscriptLib: deployedZkLib.address },
    log: true,
    waitConfirmations,
  });

  // 3. DemoDao (the confidential, membership-gated Governor).
  const membershipRoot = await resolveMembershipRoot();
  const deployedDao = await deploy("DemoDao", {
    from: deployer,
    args: [deployedToken.address, deployedVerifier.address, membershipRoot],
    log: true,
    waitConfirmations,
  });

  console.log(`MyToken contract:      ${deployedToken.address}`);
  console.log(`ZKTranscriptLib:       ${deployedZkLib.address}`);
  console.log(`HonkVerifier contract: ${deployedVerifier.address}`);
  console.log(`DemoDao contract:      ${deployedDao.address}`);
  console.log(`Membership root:       ${membershipRoot}`);
  if (!process.env.MEMBERSHIP_ROOT) {
    console.log(`Demo member identity secrets: [${DEMO_IDENTITY_SECRETS.join(", ")}]`);
    console.log(`Demo member addresses (used as secrets): [${DEMO_MEMBER_ADDRESSES.join(", ")}]`);
  }

  if (deployedDao.newlyDeployed) {
    const dao = await ethers.getContractAt("DemoDao", deployedDao.address);
    console.log(`DemoDao.token():                 ${await dao.token()}`);
    console.log(`DemoDao.voteSubmissionVerifier(): ${await dao.voteSubmissionVerifier()}`);
    console.log(`DemoDao.membershipRoot():         ${await dao.membershipRoot()}`);
  }
};

export default func;
func.id = "deploy_demo_dao";
func.tags = ["DemoDao", "HonkVerifier", "MyToken"];
