# LocalDAO - Decentralized Autonomous Organization for Local Communities

## Overview

LocalDAO is a comprehensive smart contract system designed to enable local communities to form Decentralized Autonomous Organizations (DAOs) for collective investment, governance, and treasury management. The system allows community members to propose investments, vote on proposals using staked USDC, and receive proportional yield distributions.

## Table of Contents

- [Architecture](#architecture)
- [Key Features](#key-features)
- [Contracts](#contracts)
- [Core Functionality](#core-functionality)
- [Security Features](#security-features)
- [Installation & Setup](#installation--setup)
- [Usage Guide](#usage-guide)
- [Roles & Permissions](#roles--permissions)
- [Investment Lifecycle](#investment-lifecycle)
- [Yield Distribution](#yield-distribution)
- [Events](#events)
- [Security Considerations](#security-considerations)

## Architecture

The LocalDAO system consists of three main components:

### 1. **LocalDAOFactory** (`src/LocalDAOFactory.sol`)
- Factory contract for deploying new LocalDAO instances
- Maintains registry of all deployed DAOs
- Provides metadata and validation functions

### 2. **LocalDAO** (`src/LocalDAO.sol`)
- Core DAO contract managing:
  - Member management and KYC verification
  - Investment proposal creation and voting
  - Yield distribution and treasury management
  - Admin and finance manager roles

### 3. **Supporting Libraries**
- **InvestmentManager** (`src/libraries/InvestmentManager.sol`): Investment lifecycle logic
- **YieldCalculator** (`src/libraries/YieldCalculator.sol`): Yield calculation and distribution

## Key Features

✅ **Member Management**: KYC-verified membership system with configurable limits  
✅ **Investment Proposals**: Create, vote, and manage investment opportunities  
✅ **Stake-Based Voting**: Upvote with USDC staking, downvote for free  
✅ **Yield Distribution**: Proportional yield distribution to upvoters  
✅ **Treasury Recovery**: Grace period mechanism for unclaimed yield  
✅ **Role-Based Access**: Creator, Admin, and Finance Manager roles  
✅ **Pausable**: Emergency pause functionality  
✅ **Reentrancy Protection**: Safe from reentrancy attacks  
✅ **Safe Token Handling**: Uses SafeERC20 for secure token transfers  

## Contracts

### LocalDAOFactory

**Purpose**: Deploy and manage LocalDAO instances

**Key Functions**:
- `createDAO(...)`: Deploy a new LocalDAO with specified parameters
- `getAllDAOs()`: Retrieve all deployed DAO addresses
- `getActiveDAOs()`: Get only active DAOs
- `isValidDAO(address)`: Verify if an address is a valid DAO
- `deactivateDAO(address)`: Emergency deactivation (owner only)

### LocalDAO

**Purpose**: Core DAO functionality

**Key State Variables**:
- `name`, `description`, `location`: DAO identity
- `maxMembership`: Maximum member limit
- `creator`: DAO creator address
- `usdcAddress`: USDC token address
- `totalValueLocked`: Total staked USDC

**Enums**:
- `Status`: PENDING, ACTIVE, ENDED, INCOMPLETE
- `Category`: HEALTH, EDUCATION, ENTERTAINMENT, AGRICULTURE, TECHNOLOGY, RETAIL, OTHER
- `Grade`: A, B, C, D (affects deadline extension eligibility)

## Core Functionality

### Member Management

#### `addMember(address wallet, bytes32 kycProofHash)`
- **Access**: Admin only
- **Purpose**: Add a new member to the DAO
- **Process**: 
  1. Admin adds member with KYC proof hash
  2. Member is added but KYC status is `false`
  3. Admin must call `verifyMemberKYC()` after off-chain verification

#### `verifyMemberKYC(address wallet)`
- **Access**: Admin only
- **Purpose**: Verify member's KYC status
- **Off-chain**: Admin should verify KYC documents before calling

#### `removeMember(address wallet)`
- **Access**: Admin only
- **Purpose**: Remove a member from the DAO
- **Note**: Removed members can still claim yield if they have stake

#### `exitDAO()`
- **Access**: Member only
- **Purpose**: Allow member to voluntarily exit
- **Note**: Exiting members lose voting rights but retain yield claim rights

### Investment Management

#### `createInvestment(...)`
- **Access**: Admin only
- **Parameters**:
  - `name`: Investment name
  - `category`: Investment category enum
  - `fundNeeded`: Required funding in USDC
  - `expectedYield`: Expected yield percentage (0-100)
  - `grade`: Investment grade (A, B, C, D)
  - `deadline`: Voting deadline in days (1-365)
  - `documentCIDs`: Array of IPFS/document CIDs
- **Returns**: Investment ID

#### `vote(uint256 investmentId, uint256 numberOfVotes, uint8 voteValue)`
- **Access**: Verified members only
- **Parameters**:
  - `investmentId`: Investment to vote on
  - `numberOfVotes`: USDC amount to stake (0 for downvote, >0 for upvote)
  - `voteValue`: 1 for upvote, 0 for downvote
- **Process**:
  - Upvote: Requires USDC staking, transfers USDC to contract
  - Downvote: Free, increments downvote counter
- **Note**: One vote per member per investment

#### `activateInvestment(uint256 investmentId)`
- **Access**: Admin only
- **Requirements**:
  - Investment status must be PENDING
  - `upvotes >= fundNeeded`
  - Deadline must not have passed
- **Effect**: Changes status to ACTIVE

#### `markInvestmentIncomplete(uint256 investmentId)`
- **Access**: Admin only
- **Requirements**:
  - Investment status must be PENDING
  - `upvotes < fundNeeded`
  - Deadline has passed
- **Effect**: Changes status to INCOMPLETE, allows stake withdrawal

#### `extendDeadline(uint256 investmentId, uint256 additionalDays)`
- **Access**: Finance Manager only
- **Requirements**:
  - Investment grade must be A or B
  - Extension count < MAX_EXTENSIONS (3)
  - `additionalDays` between 1-90
- **Effect**: Extends voting deadline

#### `closeInvestment(uint256 investmentId)`
- **Access**: Admin only
- **Requirements**:
  - Investment status must be ACTIVE
  - All yield must be distributed (`totalYieldGenerated == totalYieldDistributed`)
- **Effect**: Changes status to ENDED

### Yield Management

#### `depositYield(uint256 investmentId, uint256 yieldAmount, string expenseReportCID)`
- **Access**: Finance Manager only
- **Purpose**: Deposit yield generated from an active investment
- **Parameters**:
  - `investmentId`: Active investment ID
  - `yieldAmount`: Yield amount in USDC
  - `expenseReportCID`: IPFS CID of expense report
- **Off-chain**: Finance manager should verify yield amount matches actual returns

#### `claimYield(uint256 investmentId)`
- **Access**: Anyone with stake (including former members)
- **Purpose**: Claim proportional yield share
- **Requirements**:
  - Investment status must be ACTIVE
  - User must have upvoted (staked)
  - User must not have already claimed
- **Calculation**: `(userStake / totalStaked) * totalYieldGenerated`
- **Note**: Former members can claim yield even after exiting DAO

#### `sweepUnclaimedYield(uint256 investmentId, address recipient)`
- **Access**: Admin only
- **Purpose**: Recover unclaimed yield after grace period
- **Requirements**:
  - Investment status must be ENDED
  - Grace period (90 days) must have passed since last yield deposit
  - Unclaimed yield must exist
- **Effect**: Transfers unclaimed yield to recipient (typically DAO treasury)

### Refunds

#### `withdrawStake(uint256 investmentId)`
- **Access**: Anyone with stake
- **Purpose**: Withdraw staked USDC from incomplete investments
- **Requirements**:
  - Investment status must be INCOMPLETE
  - User must have staked (upvoted)
- **Effect**: Returns staked USDC to user

## Security Features

### 1. **SafeERC20 Integration**
- All token transfers use SafeERC20 library
- Handles non-standard ERC20 tokens safely
- Prevents silent failures

### 2. **Reentrancy Protection**
- Critical functions use `nonReentrant` modifier
- Prevents reentrancy attacks

### 3. **Pausable Contract**
- Emergency pause functionality
- Only creator can pause/unpause
- Prevents all state-changing operations when paused

### 4. **Access Control**
- Role-based access control (Creator, Admin, Finance Manager)
- Modifiers enforce permissions
- Clear separation of concerns

### 5. **Input Validation**
- Comprehensive parameter validation
- Explicit error messages
- Bounds checking (e.g., deadline 1-365 days)

### 6. **Yield Distribution Safety**
- Validation prevents over-distribution
- Grace period for unclaimed yield recovery
- Former members can claim yield (prevents fund lock)

## Installation & Setup

### Prerequisites
- Node.js and npm
- Foundry (for testing and deployment)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd Mantle_Hack

# Install dependencies (if using npm)
npm install

# Install Foundry dependencies
forge install
```

### Compilation

```bash
forge build
```

### Testing

```bash
forge test
```

### Deployment

Deploy in this order:
1. Deploy LocalDAOFactory
2. Use factory to deploy LocalDAO instances

## Usage Guide

### Creating a DAO

```solidity
// Deploy factory (one-time)
LocalDAOFactory factory = new LocalDAOFactory(owner);

// Create a new DAO
address daoAddress = factory.createDAO(
    "Essien Town Local DAO",
    "Community investment DAO",
    "Essien Town",
    "6.5244,3.3792",
    "100001",
    100,  // maxMembership
    usdcTokenAddress
);
```

### Adding Members

```solidity
LocalDAO dao = LocalDAO(daoAddress);

// Admin adds member
bytes32 kycHash = keccak256(abi.encodePacked(kycDocument));
dao.addMember(memberAddress, kycHash);

// Admin verifies KYC (after off-chain verification)
dao.verifyMemberKYC(memberAddress);
```

### Creating and Voting on Investments

```solidity
// Admin creates investment
uint256 investmentId = dao.createInvestment(
    "Local Farm Investment",
    LocalDAO.Category.AGRICULTURE,
    10000 * 1e6,  // $10,000 USDC
    15,           // 15% expected yield
    LocalDAO.Grade.A,
    30,           // 30 days voting period
    documentCIDs
);

// Member votes (upvote with stake)
IERC20(usdc).approve(daoAddress, 1000 * 1e6);
dao.vote(investmentId, 1000 * 1e6, 1);  // 1 = upvote

// Admin activates if funding goal met
dao.activateInvestment(investmentId);
```

### Depositing and Claiming Yield

```solidity
// Finance manager deposits yield
IERC20(usdc).approve(daoAddress, 1500 * 1e6);
dao.depositYield(investmentId, 1500 * 1e6, expenseReportCID);

// Members claim proportional yield
dao.claimYield(investmentId);
```

## Roles & Permissions

### Creator
- **Powers**:
  - Add/remove admins
  - Add/remove finance managers
  - Pause/unpause contract
- **Limitations**: Cannot directly manage investments

### Admin
- **Powers**:
  - Add/remove members
  - Verify member KYC
  - Create investments
  - Activate investments
  - Mark investments incomplete
  - Close investments
  - Update DAO info
- **Limitations**: Cannot deposit yield or extend deadlines

### Finance Manager
- **Powers**:
  - Deposit yield
  - Extend deadlines (Grade A/B only)
- **Limitations**: Cannot create or activate investments

### Verified Members
- **Powers**:
  - Vote on investments
  - Claim yield (if staked)
  - Exit DAO
- **Limitations**: Cannot create investments or manage members

## Investment Lifecycle

```
1. PENDING
   ├─ Admin creates investment proposal
   ├─ Members vote (upvote/downvote)
   ├─ Admin can extend deadline (Grade A/B, max 3 times)
   │
   ├─ If upvotes >= fundNeeded AND deadline not passed:
   │   └─ Admin activates → ACTIVE
   │
   └─ If upvotes < fundNeeded AND deadline passed:
       └─ Admin marks incomplete → INCOMPLETE
           └─ Members can withdraw stake

2. ACTIVE
   ├─ Finance manager deposits yield
   ├─ Members claim proportional yield
   │
   └─ If all yield distributed:
       └─ Admin closes → ENDED

3. ENDED
   ├─ Investment complete
   └─ After 90 days grace period:
       └─ Admin can recover unclaimed yield
```

## Yield Distribution

### Calculation Formula

```
userYield = (userStake / totalStaked) * totalYieldGenerated
```

### Example

- Total staked: 10,000 USDC
- User stake: 1,000 USDC (10%)
- Total yield generated: 1,500 USDC
- User yield: (1,000 / 10,000) * 1,500 = 150 USDC

### Distribution Rules

1. Only upvoters (stakers) can claim yield
2. Yield is distributed proportionally based on stake
3. Users can claim yield even after exiting DAO
4. Unclaimed yield can be recovered after 90-day grace period

## Events

### Member Events
- `MemberAdded(address indexed member, uint256 timestamp)`
- `MemberKYCVerified(address indexed member, uint256 timestamp)`
- `MemberRemoved(address indexed member, uint256 timestamp)`
- `MemberExited(address indexed member, uint256 timestamp)`

### Investment Events
- `InvestmentCreated(uint256 indexed investmentId, string name, uint256 fundNeeded, Grade grade, uint256 deadline)`
- `InvestmentActivated(uint256 indexed investmentId, uint256 timestamp)`
- `InvestmentClosed(uint256 indexed investmentId, uint256 timestamp)`
- `InvestmentIncomplete(uint256 indexed investmentId, uint256 timestamp)`
- `DeadlineExtended(uint256 indexed investmentId, uint256 newDeadline, uint256 extensionCount)`

### Voting Events
- `VoteCast(uint256 indexed investmentId, address indexed voter, uint256 numberOfVotes, uint8 voteValue, uint256 timestamp)`
- `StakeWithdrawn(uint256 indexed investmentId, address indexed voter, uint256 amount)`

### Yield Events
- `YieldDeposited(uint256 indexed investmentId, uint256 amount, string expenseReportCID, uint256 timestamp)`
- `YieldClaimed(uint256 indexed investmentId, address indexed voter, uint256 amount, uint256 timestamp)`
- `UnclaimedYieldRecovered(uint256 indexed investmentId, address indexed recipient, uint256 amount, uint256 timestamp)`

### Admin Events
- `AdminAdded(address indexed admin)`
- `AdminRemoved(address indexed admin)`
- `FinanceManagerAdded(address indexed manager)`
- `FinanceManagerRemoved(address indexed manager)`
- `DAOPaused(uint256 timestamp)`
- `DAOUnpaused(uint256 timestamp)`

## Security Considerations

### Centralization Risks

⚠️ **Important**: This system is **permissioned and centralized**:
- Creator has ultimate control (can pause, add/remove admins)
- Admins control investment creation and activation
- Finance managers control yield deposits

**Mitigation**: 
- Use multi-sig wallets for creator/admin roles
- Implement timelocks for critical operations
- Consider governance token for future decentralization

### Off-Chain Dependencies

- **KYC Verification**: Admin must verify KYC documents off-chain before calling `verifyMemberKYC()`
- **Yield Verification**: Finance manager must verify actual yield matches deposit amount
- **Document Storage**: Investment documents stored off-chain (IPFS)

### Best Practices

1. **Multi-sig Wallets**: Use multi-sig for creator/admin roles
2. **KYC Process**: Establish clear off-chain KYC verification process
3. **Yield Auditing**: Regular audits of yield deposits vs. actual returns
4. **Member Limits**: Set appropriate `maxMembership` based on community size
5. **Investment Grades**: Use grades appropriately (only A/B can extend deadlines)
6. **Grace Periods**: Monitor and recover unclaimed yield after grace period

## Constants

- `MAX_EXTENSIONS`: 3 (maximum deadline extensions per investment)
- `GRACE_PERIOD_FOR_UNCLAIMED_YIELD`: 90 days

## License

MIT License

## Contributing

Contributions are welcome! Please ensure:
- Code follows Solidity style guide
- All tests pass
- Security best practices are followed
- Documentation is updated

## Support

For issues, questions, or contributions, please open an issue on the repository.

---

**Built with ❤️ for local communities**
