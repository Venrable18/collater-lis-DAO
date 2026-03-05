# LocalDAO & LocalDAOFactory – Overview

This project lets local communities (like Essien Town) create their own DAO, collect stablecoins (USDC on Avalanche Fuji), vote on projects, and share the profits from those projects.

There are two main contracts:

- `LocalDAOFactory`: creates DAOs as cheap proxy contracts.
- `LocalDAO`: the main DAO logic (members, investments, voting, funds, yield).

---

## High-Level Flow

1. **Factory owner** deploys `LocalDAO` implementation + `LocalDAOFactory`.
2. **Community leader** calls the factory to create a new DAO.
3. **Creator / admins** onboard members and list investment proposals.
4. **Members** stake USDC to upvote (fund) good projects, or downvote them.
5. **Finance managers** deposit yield when investments make money.
6. **Members** claim their share of the yield based on how much they staked.
7. **Admins** close fully-distributed investments and can sweep unclaimed yield to the DAO treasury after a grace period.

---

## LocalDAOFactory

### Purpose

- Deploy DAOs as **EIP‑1167 “minimal proxy” clones** of a single `LocalDAO` implementation.
- Track all DAOs it has created.

### Key State

- `implementation`: address of the main `LocalDAO` logic contract.
- `allDAOs`: list of all DAO addresses.
- `isDAO[dao]`: marks which addresses are valid DAOs.
- `daoInfo[dao]`: stores basic info (name, location, creator, createdAt, isActive).

### Important Functions

- `constructor(address _owner, address _implementation)`
  - Sets who owns the factory and which `LocalDAO` implementation it will clone.

- `createDAO(name, description, location, coordinates, postalCode, maxMembership, usdcAddress)`
  - Clones the `LocalDAO` implementation.
  - Calls `initialize(...)` on the clone with human-readable info + the stablecoin address (USDC on Fuji).
  - Saves metadata and returns the new DAO address.
  - **Who calls it**: anyone (typically the community leader).

- `getAllDAOs()`
  - Returns all DAO addresses ever created.

- `getActiveDAOs()`
  - Returns only DAOs that are currently marked active.

- `isValidDAO(daoAddress)`
  - Returns `true` if the address is a DAO created by this factory and still active.

- `getDAOMetadata(daoAddress)`
  - Returns name, location, creator, createdAt, and isActive for a DAO.

- `deactivateDAO(daoAddress)` (only factory owner)
  - Marks a DAO as inactive in metadata (does not touch DAO logic directly).
  - Useful if a DAO needs to be delisted / “warned” at the factory level.

---

## LocalDAO

### Purpose

One deployed per community. Handles:

- DAO identity (name, description, location).
- Membership and KYC flags.
- Creating investment proposals.
- Voting with staked USDC.
- Yield deposits and yield sharing.
- Admin and finance manager controls.
- Activity timeline / audit log.

### Identity & Basic Info

Public variables:

- `name`, `description`, `location`, `coordinates`, `postalCode`, `logoURI`
- `maxMembership`: maximum allowed members.
- `creator`: the original creator (has special admin powers).
- `usdcAddress`: the stablecoin used for staking & yield (USDC on Fuji).
- `totalValueLocked`: total USDC currently staked in active investments.

---

## Initialization & Roles

- `initialize(creator, name, description, location, coordinates, postalCode, maxMembership, usdcAddress)`
  - Called once by the factory on the clone.
  - Sets the DAO’s identity, maximum members, and USDC token.
  - **Not** a constructor – this is proxy-safe initialization.

**Roles:**

- `creator`:
  - Can add/remove admins.
  - Can add/remove finance managers.
  - Can pause/unpause the whole DAO.

- `admins`:
  - Onboard/remove/verify members.
  - Create investment proposals.
  - Activate or mark investments as incomplete.
  - Close fully-distributed investments.
  - Sweep unclaimed yield after grace period.
  - Update DAO info (description/logo).

- `finance managers`:
  - Extend investment deadlines (within strict rules).
  - Deposit yield into successful investments.

- `members`:
  - Must be active + KYC-verified to vote.
  - Can exit the DAO but still claim yield on past stakes.

---

## Membership Functions

- `addMember(wallet, kycProofHash)` (only admin)
  - Adds a new member, marks them active and KYC-verified.
  - Increases `memberCount`.

- `verifyMemberKYC(wallet)` (only admin)
  - Marks an existing member as KYC-verified.

- `removeMember(wallet)` (only admin)
  - Marks the member as inactive and decreases `memberCount`.
  - They can still claim yield if they previously staked.

- `exitDAO()` (member)
  - Lets a member voluntarily leave the DAO.
  - Sets them inactive and decreases `memberCount`, but keeps their past staking history so they can still claim yield.

- `getAllMembers()`
  - Returns the array of all member addresses ever added.

- `isVerifiedMember(wallet)`
  - Returns `true` only if the member is active and KYC-verified.

---

## Investment Lifecycle

Each investment (project) has:

- `id`, `name`, `status` (PENDING, ACTIVE, ENDED, INCOMPLETE)
- `category` (HEALTH, EDUCATION, etc.)
- `deadline` (timestamp for voting to end)
- `upvotes` (total USDC staked in support)
- `downvotes` (number of downvotes)
- `fundNeeded` (USDC goal)
- `expectedYield` (percentage)
- `grade` (A, B, C, D – affects deadline extension rules)
- `documentCIDs` (proposal docs)
- Yield stats: `totalYieldGenerated`, `totalYieldDistributed`, `extensionCount`, `createdAt`, `createdBy`.

### Investment Functions

- `createInvestment(name, category, fundNeeded, expectedYield, grade, deadlineDays, documentCIDs)` (only admin)
  - Creates a new proposal in `PENDING` status.
  - Calculates `deadline` as `now + deadlineDays`.

- `getInvestment(id)`
  - Returns full details for one investment.

- `getAllInvestments()`
  - Returns the list of all investments.

- `getInvestmentsByStatus(status)`
  - Returns only investments in the given status (e.g. all PENDING).

---

## Voting & Staking

**Key ideas:**

- Voting is **one USDC = one upvote** (you actually stake USDC).
- Members can **add more votes later** by staking more USDC.
- Downvotes cost nothing, but you can only downvote once per investment.

Data:

- `votes[investmentId][voter]`:
  - `numberOfVotes` (how many USDC units they staked)
  - `voteValue` (1 = upvote, 0 = downvote)
  - `hasClaimedYield`, `yieldClaimed`

### Functions

- `vote(investmentId, numberOfVotes, voteValue)` (only verified member)
  - Checks investment is `PENDING` and before `deadline`.
  - `voteValue = 1` (upvote):
    - Requires `numberOfVotes > 0`.
    - Transfers that amount of USDC from the voter to the DAO.
    - **Accumulates** stake: member can call multiple times to add more upvotes.
    - Increases `inv.upvotes` and `totalValueLocked`.
  - `voteValue = 0` (downvote):
    - Requires `numberOfVotes == 0`.
    - Allowed only if the voter hasn’t voted before on that investment.
    - Increases `inv.downvotes`.

- `getVote(investmentId, voter)`
  - Returns the stored vote record.

- `getVoteCounts(investmentId)`
  - Returns `(upvotes, downvotes)` totals.

---

## Activating / Failing Investments

- `activateInvestment(investmentId)` (only admin)
  - Uses helper rules from `InvestmentManager` to check:
    - Upvotes (funding) are sufficient.
    - Deadline has not passed.
  - Sets status to `ACTIVE` and increments `activeInvestmentCount`.

- `markInvestmentIncomplete(investmentId)` (only admin)
  - When voting ends and upvotes are too low.
  - Uses helper rules to confirm it should be incomplete.
  - Sets status to `INCOMPLETE`.

---

## Refunds

- `withdrawStake(investmentId)` (any staker)
  - Only if investment is `INCOMPLETE`.
  - Sends back all USDC they staked on that investment.
  - Decreases `totalValueLocked`.

- `getWithdrawableAmount(investmentId, voter)`
  - Returns how much USDC the voter can withdraw if the investment is incomplete.

---

## Yield (Profit Sharing)

When an investment returns profits, the DAO shares it among upvoters.

- `depositYield(investmentId, yieldAmount, expenseReportCID)` (only finance manager)
  - Only allowed if the investment is `ACTIVE`.
  - Transfers `yieldAmount` USDC from the finance manager to the DAO.
  - Increases `inv.totalYieldGenerated` and records it in `yieldDistributions`.

- `claimYield(investmentId)` (any staker on that investment)
  - Only for upvoters who haven’t claimed yet.
  - Calculates:
    - `userShare = userStake / totalUpvotes * totalYieldGenerated`.
  - Makes sure total payouts don’t exceed total yield.
  - Marks user as having claimed and sends their share of USDC.

- `calculateClaimableYield(investmentId, voter)`
  - Read-only: tells a voter how much yield they can claim right now.

- `getYieldDistribution(investmentId)`
  - Returns data about total yield, distributed amount, and remaining amount.

---

## Closing & Sweeping Yield

- `closeInvestment(investmentId)` (only admin)
  - Only when all yield is distributed (checked by `InvestmentManager`).
  - Sets status to `ENDED`.
  - Decrements `activeInvestmentCount`.

- `sweepUnclaimedYield(investmentId, recipient)` (only admin)
  - Only after the investment is `ENDED` and a 90-day grace period has passed.
  - Transfers any leftover (unclaimed) yield to a chosen recipient (usually the DAO treasury).
  - Logs the event for transparency.

---

## Activity Timeline

For transparency and presentations, every major action is logged.

- `_addActivity(investmentId, eventType, details, documentCID)` (internal)
  - Saves a record to `investmentTimeline[investmentId]`.
  - Also emits `ActivityLogged` event.

- `getInvestmentTimeline(investmentId)`
  - Returns the list of all timeline entries (what happened, when, and by whom).

---

## Admin / Emergency Controls

- `addAdmin(admin)`, `removeAdmin(admin)` (only creator)
  - Manage the core team who can manage members and investments.

- `addFinanceManager(manager)`, `removeFinanceManager(manager)` (only creator)
  - Manage addresses allowed to handle deadlines and yield deposits.

- `updateDAOInfo(newDescription, newLogoURI)` (only admin)
  - Update descriptive metadata for the DAO (used in UI).

- `pause()` / `unpause()` (only creator)
  - Pause prevents all state-changing operations (safety switch).

---

## For Your Presentation

In simple terms:

- **Factory**: “A machine that creates new local DAOs cheaply.”
- **DAO creator**: “Community leader – fills in name, location, etc. Frontend hides the USDC address.”
- **Members**: “Verified people in the community who can vote and share profits.”
- **Investments**: “Projects the DAO can fund (like hospitals, schools).”
- **Upvotes**: “People stake USDC. More stake = more votes = larger share of profits.”
- **Downvotes**: “Free way to say ‘no’, but no profit share.”
- **Yield**: “When a project returns money, the DAO deposits yield and voters claim their share.”
- **Safety**: “Admins and finance managers have limited, well-defined powers; all actions are logged and subject to deadlines and grace periods.”