import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Deploys the DemoDao stack: confidential votes token, membership-proof verifier, and the
// membership-gated Governor. The membership root must be supplied as a parameter (non-zero,
// canonical BN254 field element); see deploy/deploy.ts for computing one from member secrets.
const DemoDaoModule = buildModule("DemoDaoModule", (m) => {
  const deployer = m.getAccount(0);
  const membershipRoot = m.getParameter("membershipRoot");

  const token = m.contract("MyToken", [deployer, deployer]);

  const zkTranscriptLib = m.library("ZKTranscriptLib");
  const verifier = m.contract("HonkVerifier", [], {
    libraries: { ZKTranscriptLib: zkTranscriptLib },
  });

  const demoDao = m.contract("DemoDao", [token, verifier, membershipRoot]);

  return { token, zkTranscriptLib, verifier, demoDao };
});

export default DemoDaoModule;
