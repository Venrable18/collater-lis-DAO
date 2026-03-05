IMPLEMENTATION  =  The original recipe / blueprint
                   (sits in a vault, nobody eats it)

FACTORY         =  The franchise office
                   (you call them to open a new branch)

DAO CLONE       =  Each actual bakery branch
                   (where customers actually go)


// constants/contracts.js

export const CONTRACTS = {
  // ✅ You hardcode this ONCE — never changes
  FACTORY:        "0x6b6c0eE71c703C51707A86f3bef0B4ACD9F4AB78",

  // ✅ You hardcode this ONCE — never changes  
  USDC:           "0x5425890298aed601595a70AB815c96711a31Bc65",

  // ❌ Never hardcode this — fetched dynamically
  // DAO clones are created at runtime, stored in state
}

export const CHAIN = {
  id:  43113,
  rpc: "https://api.avax-test.network/ext/bc/C/rpc",
  name: "Avalanche Fuji Testnet"
}


How to Handle DAO Addresses
The DAO clone addresses are dynamic — they grow as users create new communities. You fetch them from the factory, not hardcode them.

// hooks/useDAOs.js

import { CONTRACTS } from "../constants/contracts"
import FactoryABI from "../abi/LocalDAOFactory.json"

// Fetch all DAOs ever created
export async function getAllDAOs(provider) {
  const factory = new ethers.Contract(
    CONTRACTS.FACTORY,
    FactoryABI,
    provider
  )
  
  const daoAddresses = await factory.getAllDAOs()
  // returns: ["0xD10f57c96...", "0xABC123...", "0xDEF456..."]
  return daoAddresses
}



// hooks/useDAOs.js

import { CONTRACTS } from "../constants/contracts"
import FactoryABI from "../abi/LocalDAOFactory.json"

// Fetch all DAOs ever created
export async function getAllDAOs(provider) {
  const factory = new ethers.Contract(
    CONTRACTS.FACTORY,
    FactoryABI,
    provider
  )
  
  const daoAddresses = await factory.getAllDAOs()
  // returns: ["0xD10f57c96...", "0xABC123...", "0xDEF456..."]
  return daoAddresses
}




Talking to a Specific DAO
Once you have a DAO address (from getAllDAOs or from a createDAO event), you talk to it directly:

// hooks/useDAO.js

import LocalDAOABI from "../abi/LocalDAO.json"

export function getDAOContract(daoAddress, signerOrProvider) {
  return new ethers.Contract(daoAddress, LocalDAOABI, signerOrProvider)
}

// Usage anywhere in your app:
const dao = getDAOContract("0xD10f57c96...", signer)

await dao.addMember(walletAddress, kycProofHash)
await dao.createInvestment(name, category, fundNeeded, yield, grade, deadline, [])
await dao.vote(investmentId, amount, voteValue)
await dao.claimYield(investmentId)


Creating a New DAO (Full Flow)

async function createNewDAO(signer, daoDetails) {
  const factory = new ethers.Contract(
    CONTRACTS.FACTORY,
    FactoryABI,
    signer
  )

  const tx = await factory.createDAO(
    daoDetails.name,
    daoDetails.description,
    daoDetails.location,
    daoDetails.coordinates,
    daoDetails.postalCode,
    daoDetails.maxMembers,
    CONTRACTS.USDC           // ← always pass USDC address
  )

  const receipt = await tx.wait()
  
  // The new DAO address comes from the event logs
  const newDAOAddress = receipt.logs[0].args.daoAddress
  
  return newDAOAddress  // save this to your DB or state
}


USDC Approval Before Voting
This is the step people always forget. Before vote(), the user must approve USDC spending:

async function approveAndVote(signer, daoAddress, investmentId, usdcAmount) {
  // Step 1 — Approve USDC spending
  const usdc = new ethers.Contract(CONTRACTS.USDC, ERC20_ABI, signer)
  await usdc.approve(daoAddress, usdcAmount)

  // Step 2 — Now vote
  const dao = getDAOContract(daoAddress, signer)
  await dao.vote(investmentId, usdcAmount, 1)  // 1 = upvote
}
```

---

## Your ABI Files

Get them from your Foundry build output:
```
your-project/
  out/
    LocalDAO.sol/
      LocalDAO.json         ← copy the "abi" array → LocalDAO.json
    LocalDAOFactory.sol/
      LocalDAOFactory.json  ← copy the "abi" array → LocalDAOFactory.json

frontend/
  src/
    abi/
      LocalDAO.json         ← paste here
      LocalDAOFactory.json  ← paste here
    constants/
      contracts.js          ← addresses go here


