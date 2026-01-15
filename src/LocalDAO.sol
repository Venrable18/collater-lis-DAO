// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {YieldCalculator} from "./libraries/YieldCalculator.sol";
import {InvestmentManager} from "./libraries/InvestmentManager.sol";
import {ILocalDAO} from "./interfaces/ILocalDAO.sol";

/**
 * @title LocalDAO
 * @notice Core DAO contract for governance, investments, and treasury management
 * @dev Implements ILocalDAO interface for standardized interactions
 * @dev Uses SafeERC20 for secure token transfers
 */
contract LocalDAO is ILocalDAO, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ===== ENUMS =====
    enum Status { PENDING, ACTIVE, ENDED, INCOMPLETE }
    enum Category { HEALTH, EDUCATION, ENTERTAINMENT, AGRICULTURE, TECHNOLOGY, RETAIL, OTHER }
    enum Grade { A, B, C, D }

    // ===== DAO IDENTITY =====
    string public name;
    string public description;
    string public location;
    string public coordinates;
    string public postalCode;
    string public logoURI;
    uint256 public maxMembership;

    // ===== ROLES =====
    address public creator;
    address[] public admins;
    mapping(address => bool) public isAdmin;
    mapping(address => bool) public isFinanceManager;

    // ===== MEMBERS =====
    struct User {
        address wallet;
        bool kycVerified;
        bytes32 kycProofHash;
        uint256 joinedAt;
        bool isActive;
    }
    mapping(address => User) public members;
    address[] public memberAddresses;
    uint256 public memberCount;

    // ===== INVESTMENTS =====
    struct Investment {
        uint256 id;
        string name;
        Status status;
        Category category;
        uint256 deadline;
        uint256 upvotes;
        uint256 downvotes;
        uint256 fundNeeded;
        uint256 expectedYield;
        Grade grade;
        string[] documentCIDs;
        uint256 totalYieldGenerated;
        uint256 totalYieldDistributed;
        uint256 extensionCount;
        uint256 createdAt;
        address createdBy;
    }
    mapping(uint256 => Investment) public investments;
    uint256 public investmentCount;
    uint256 public activeInvestmentCount;

    // ===== VOTING =====
    struct Vote {
        address voter;
        uint256 investmentId;
        uint256 numberOfVotes;
        uint8 voteValue; // 1 = upvote, 0 = downvote
        uint256 timestamp;
        bool hasClaimedYield;
        uint256 yieldClaimed;
    }
    mapping(uint256 => mapping(address => Vote)) public votes;

    // ===== YIELD TRACKING =====
    struct YieldDistribution {
        uint256 investmentId;
        uint256 totalAmount;
        uint256 distributedAmount;
        uint256 remainingAmount;
        string expenseReportCID;
        uint256 timestamp;
    }
    mapping(uint256 => YieldDistribution) public yieldDistributions;

    // ===== ACTIVITY TIMELINE =====
    struct Activity {
        string eventType;
        uint256 timestamp;
        string details;
        string documentCID;
        address actor;
    }
    mapping(uint256 => Activity[]) public investmentTimeline;

    // ===== TREASURY =====
    address public usdcAddress;
    uint256 public totalValueLocked;

    // ===== CONSTANTS =====
    uint256 public constant MAX_EXTENSIONS = 3;
    uint256 public constant GRACE_PERIOD_FOR_UNCLAIMED_YIELD = 90 days; // 90 days grace period before recovery

    // ===== MODIFIERS =====
    modifier onlyCreator() {
        require(msg.sender == creator, "Not creator");
        _;
    }

    modifier onlyAdmin() {
        require(isAdmin[msg.sender] || msg.sender == creator, "Not admin");
        _;
    }

    modifier onlyFinanceManager() {
        require(
            isFinanceManager[msg.sender] || 
            isAdmin[msg.sender] || 
            msg.sender == creator,
            "Not authorized"
        );
        _;
    }

    modifier onlyVerifiedMember() {
        require(members[msg.sender].isActive, "Not active member");
        require(members[msg.sender].kycVerified, "KYC not verified");
        _;
    }

    /**
     * @notice Modifier to check if user has stake in an investment (for yield claiming)
     * @dev Allows former members to claim yield if they have stake
     */
    modifier hasStakeInInvestment(uint256 investmentId) {
        Vote storage userVote = votes[investmentId][msg.sender];
        require(userVote.numberOfVotes > 0, "No stake in investment");
        require(userVote.voteValue == 1, "Only upvoters can claim yield");
        _;
    }

    modifier investmentExists(uint256 investmentId) {
        require(investmentId > 0 && investmentId <= investmentCount, "Invalid investment");
        _;
    }

    // ===== CONSTRUCTOR =====
    constructor(
        address _creator,
        string memory _name,
        string memory _description,
        string memory _location,
        string memory _coordinates,
        string memory _postalCode,
        uint256 _maxMembership,
        address _usdcAddress
    ) {
        require(_creator != address(0), "Invalid creator");
        require(_usdcAddress != address(0), "Invalid USDC address");
        
        creator = _creator;
        name = _name;
        description = _description;
        location = _location;
        coordinates = _coordinates;
        postalCode = _postalCode;
        maxMembership = _maxMembership;
        usdcAddress = _usdcAddress;
    }

    // ===== MEMBER MANAGEMENT =====
    /**
     * @notice Add a new member to the DAO
     * @dev Only admins can add members. KYC verification happens separately via verifyMemberKYC
     * @dev Off-chain: Admin should verify KYC documents before calling verifyMemberKYC
     * @param wallet Address of the new member
     * @param kycProofHash Hash of KYC proof document (stored off-chain, verified by admin)
     */
    function addMember(address wallet, bytes32 kycProofHash) 
        external 
        onlyAdmin 
        whenNotPaused 
    {
        require(wallet != address(0), "LocalDAO: Invalid wallet address");
        require(!members[wallet].isActive, "LocalDAO: Address is already a member");
        require(memberCount < maxMembership, "LocalDAO: Maximum membership limit reached");

        members[wallet] = User({
            wallet: wallet,
            kycVerified: true,
            kycProofHash: kycProofHash,
            joinedAt: block.timestamp,
            isActive: true
        });
        memberAddresses.push(wallet);
        memberCount++;

        emit MemberAdded(wallet, block.timestamp);
    }

    /**
     * @notice Verify a member's KYC status
     * @dev Only admins can verify KYC. Admin must verify KYC documents off-chain before calling this
     * @dev Off-chain: Admin should compare kycProofHash with submitted documents before verification
     * @param wallet Address of the member to verify
     */
    function verifyMemberKYC(address wallet) external onlyAdmin whenNotPaused {
        require(members[wallet].isActive, "LocalDAO: Address is not a member");
        require(!members[wallet].kycVerified, "LocalDAO: Member KYC already verified");

        members[wallet].kycVerified = true;
        emit MemberKYCVerified(wallet, block.timestamp);
    }

    /**
     * @notice Remove a member from the DAO
     * @dev Admin function. Removed members can still claim yield if they have stake
     * @param wallet Address of the member to remove
     */
    function removeMember(address wallet) external onlyAdmin whenNotPaused {
        require(members[wallet].isActive, "LocalDAO: Address is not a member");

        members[wallet].isActive = false;
        memberCount--;

        emit MemberRemoved(wallet, block.timestamp);
    }

    /**
     * @notice Allow a member to exit the DAO voluntarily
     * @dev Members can exit even with active stakes. They can still claim yield later
     * @dev Warning: Exiting members lose voting rights but retain yield claim rights
     */
    function exitDAO() external whenNotPaused {
        require(members[msg.sender].isActive, "LocalDAO: Not a member");
        
        members[msg.sender].isActive = false;
        memberCount--;

        emit MemberExited(msg.sender, block.timestamp);
    }

    function getAllMembers() external view returns (address[] memory) {
        return memberAddresses;
    }

    function isVerifiedMember(address wallet) external view returns (bool) {
        return members[wallet].isActive && members[wallet].kycVerified;
    }

    // ===== INVESTMENT CREATION =====
    /**
     * @notice Create a new investment proposal
     * @dev Only admins can create investments. Members vote to approve funding
     * @param _name Name of the investment proposal
     * @param category Investment category (HEALTH, EDUCATION, etc.)
     * @param fundNeeded Required funding amount in USDC (must be > 0)
     * @param expectedYield Expected yield percentage (0-100, e.g., 5 = 5%)
     * @param grade Investment grade (A, B, C, or D) - affects extension eligibility
     * @param deadline Voting deadline in days (1-365 days)
     * @param documentCIDs Array of IPFS/document CIDs for proposal documents
     * @return investmentId The ID of the newly created investment
     */
    function createInvestment(
        string memory _name,
        Category category,
        uint256 fundNeeded,
        uint256 expectedYield,
        Grade grade,
        uint256 deadline,
        string[] memory documentCIDs
    ) external onlyAdmin whenNotPaused returns (uint256 investmentId) {
        require(
            InvestmentManager.validateInvestmentParams(fundNeeded, expectedYield, deadline),
            "LocalDAO: Invalid investment parameters"
        );
        require(bytes(_name).length > 0, "LocalDAO: Investment name cannot be empty");

        investmentCount++;
        investmentId = investmentCount;

        investments[investmentId] = Investment({
            id: investmentId,
            name: _name,
            status: Status.PENDING,
            category: category,
            deadline: block.timestamp + (deadline * 1 days),
            upvotes: 0,
            downvotes: 0,
            fundNeeded: fundNeeded,
            expectedYield: expectedYield,
            grade: grade,
            documentCIDs: documentCIDs,
            totalYieldGenerated: 0,
            totalYieldDistributed: 0,
            extensionCount: 0,
            createdAt: block.timestamp,
            createdBy: msg.sender
        });

        _addActivity(
            investmentId,
            "investment_created",
            "Investment proposal created",
            ""
        );

        emit InvestmentCreated(investmentId, _name, fundNeeded, grade, investments[investmentId].deadline);
        
        return investmentId;
    }

    function getInvestment(uint256 investmentId) 
        external 
        view 
        investmentExists(investmentId)
        returns (Investment memory) 
    {
        return investments[investmentId];
    }

    function getAllInvestments() external view returns (Investment[] memory) {
        Investment[] memory all = new Investment[](investmentCount);
        for (uint256 i = 1; i <= investmentCount; i++) {
            all[i - 1] = investments[i];
        }
        return all;
    }

    function getInvestmentsByStatus(Status status) 
        external 
        view 
        returns (Investment[] memory) 
    {
        uint256 count = 0;
        for (uint256 i = 1; i <= investmentCount; i++) {
            if (investments[i].status == status) {
                count++;
            }
        }

        Investment[] memory result = new Investment[](count);
        uint256 index = 0;
        for (uint256 i = 1; i <= investmentCount; i++) {
            if (investments[i].status == status) {
                result[index] = investments[i];
                index++;
            }
        }
        return result;
    }

    // ===== VOTING =====
    /**
     * @notice Cast a vote on an investment proposal
     * @dev Upvotes require USDC staking, downvotes are free
     * @dev Only verified members can vote
     * @param investmentId ID of the investment to vote on
     * @param numberOfVotes Amount of USDC to stake (must be > 0 for upvote, 0 for downvote)
     * @param voteValue 1 for upvote, 0 for downvote
     */
    function vote(
        uint256 investmentId,
        uint256 numberOfVotes,
        uint8 voteValue
    ) 
        external 
        onlyVerifiedMember 
        investmentExists(investmentId) 
        nonReentrant
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        require(inv.status == Status.PENDING, "LocalDAO: Investment is not in pending status");
        require(block.timestamp <= inv.deadline, "LocalDAO: Voting deadline has passed");
        require(voteValue <= 1, "LocalDAO: Vote value must be 0 (downvote) or 1 (upvote)");
        require(votes[investmentId][msg.sender].numberOfVotes == 0, "LocalDAO: Already voted on this investment");

        if (voteValue == 1) {
            // Upvote - requires USDC staking
            require(numberOfVotes > 0, "LocalDAO: Upvote requires staking USDC");
            require(IERC20(usdcAddress).balanceOf(msg.sender) >= numberOfVotes, "LocalDAO: Insufficient USDC balance");
            require(
                IERC20(usdcAddress).allowance(msg.sender, address(this)) >= numberOfVotes,
                "LocalDAO: Insufficient USDC allowance"
            );

            IERC20(usdcAddress).safeTransferFrom(msg.sender, address(this), numberOfVotes);
            inv.upvotes += numberOfVotes;
            totalValueLocked += numberOfVotes;
        } else {
            // Downvote - no staking required
            require(numberOfVotes == 0, "LocalDAO: Downvote requires no stake");
            inv.downvotes++;
        }

        votes[investmentId][msg.sender] = Vote({
            voter: msg.sender,
            investmentId: investmentId,
            numberOfVotes: numberOfVotes,
            voteValue: voteValue,
            timestamp: block.timestamp,
            hasClaimedYield: false,
            yieldClaimed: 0
        });

        _addActivity(
            investmentId,
            "vote_cast",
            string(abi.encodePacked("Vote cast by ", _addressToString(msg.sender))),
            ""
        );

        emit VoteCast(investmentId, msg.sender, numberOfVotes, voteValue, block.timestamp);
    }

    function getVote(uint256 investmentId, address voter)
        external
        view
        returns (Vote memory)
    {
        return votes[investmentId][voter];
    }

    function getVoteCounts(uint256 investmentId)
        external
        view
        returns (uint256 upvotes, uint256 downvotes)
    {
        Investment memory inv = investments[investmentId];
        return (inv.upvotes, inv.downvotes);
    }

    // ===== INVESTMENT ACTIVATION =====
    /**
     * @notice Activate an investment proposal after voting succeeds
     * @dev Only admins can activate. Requires upvotes >= fundNeeded and deadline not passed
     * @param investmentId ID of the investment to activate
     */
    function activateInvestment(uint256 investmentId) 
        external 
        onlyAdmin 
        investmentExists(investmentId)
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        
        require(
            InvestmentManager.canActivate(
                inv.upvotes,
                inv.fundNeeded,
                inv.deadline,
                block.timestamp
            ),
            "LocalDAO: Investment does not meet activation requirements"
        );
        require(inv.status == Status.PENDING, "LocalDAO: Investment is not in pending status");

        inv.status = Status.ACTIVE;
        activeInvestmentCount++;

        _addActivity(
            investmentId,
            "investment_active",
            "Investment activated by admin",
            ""
        );

        emit InvestmentActivated(investmentId, block.timestamp);
    }

    /**
     * @notice Mark an investment as incomplete if funding goal not met
     * @dev Only admins can mark incomplete. Requires deadline passed and upvotes < fundNeeded
     * @param investmentId ID of the investment to mark incomplete
     */
    function markInvestmentIncomplete(uint256 investmentId) 
        external 
        onlyAdmin 
        investmentExists(investmentId)
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        
        require(
            InvestmentManager.shouldMarkIncomplete(
                inv.upvotes,
                inv.fundNeeded,
                inv.deadline,
                block.timestamp
            ),
            "LocalDAO: Investment does not meet incomplete criteria"
        );
        require(inv.status == Status.PENDING, "LocalDAO: Investment is not in pending status");

        inv.status = Status.INCOMPLETE;

        _addActivity(
            investmentId,
            "investment_incomplete",
            "Investment marked as incomplete",
            ""
        );

        emit InvestmentIncomplete(investmentId, block.timestamp);
    }

    /**
     * @notice Extend the voting deadline for an investment
     * @dev Only finance managers can extend. Only Grade A and B investments can be extended
     * @dev Maximum 3 extensions per investment
     * @param investmentId ID of the investment
     * @param additionalDays Days to add (1-90 days)
     */
    function extendDeadline(
        uint256 investmentId,
        uint256 additionalDays
    ) 
        external 
        onlyFinanceManager 
        investmentExists(investmentId)
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        
        require(
            InvestmentManager.canExtendDeadline(
                InvestmentManager.Grade(uint8(inv.grade)),
                inv.extensionCount,
                MAX_EXTENSIONS
            ),
            "LocalDAO: Deadline cannot be extended (check grade and extension limit)"
        );
        require(additionalDays > 0 && additionalDays <= 90, "LocalDAO: Extension must be between 1 and 90 days");

        inv.deadline = InvestmentManager.calculateNewDeadline(inv.deadline, additionalDays);
        inv.extensionCount++;

        _addActivity(
            investmentId,
            "deadline_extended",
            string(abi.encodePacked("Deadline extended by ", _uintToString(additionalDays), " days")),
            ""
        );

        emit DeadlineExtended(investmentId, inv.deadline, inv.extensionCount);
    }

    function canActivateInvestment(uint256 investmentId)
        external
        view
        investmentExists(investmentId)
        returns (bool)
    {
        Investment memory inv = investments[investmentId];
        return InvestmentManager.canActivate(
            inv.upvotes,
            inv.fundNeeded,
            inv.deadline,
            block.timestamp
        );
    }

    // ===== REFUNDS =====
    /**
     * @notice Withdraw staked USDC from an incomplete investment
     * @dev Can be called by anyone who staked, even if they're no longer a member
     * @param investmentId ID of the incomplete investment
     */
    function withdrawStake(uint256 investmentId)
        external
        investmentExists(investmentId)
        nonReentrant
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        require(inv.status == Status.INCOMPLETE, "LocalDAO: Investment is not incomplete");

        Vote storage userVote = votes[investmentId][msg.sender];
        require(userVote.numberOfVotes > 0, "LocalDAO: No stake to withdraw");

        uint256 amount = userVote.numberOfVotes;
        userVote.numberOfVotes = 0;
        totalValueLocked -= amount;

        IERC20(usdcAddress).safeTransfer(msg.sender, amount);

        emit StakeWithdrawn(investmentId, msg.sender, amount);
    }

    function getWithdrawableAmount(uint256 investmentId, address voter)
        external
        view
        investmentExists(investmentId)
        returns (uint256)
    {
        Investment memory inv = investments[investmentId];
        if (inv.status != Status.INCOMPLETE) {
            return 0;
        }

        Vote memory userVote = votes[investmentId][voter];
        return userVote.numberOfVotes;
    }

    // ===== YIELD MANAGEMENT =====
    /**
     * @notice Deposit yield generated from an active investment
     * @dev Only finance managers can deposit yield. Must provide expense report CID
     * @dev Off-chain: Finance manager should verify yield amount matches actual returns before depositing
     * @param investmentId ID of the active investment
     * @param yieldAmount Amount of yield in USDC to deposit
     * @param expenseReportCID IPFS CID of expense report document
     */
    function depositYield(
        uint256 investmentId,
        uint256 yieldAmount,
        string memory expenseReportCID
    ) 
        external 
        onlyFinanceManager 
        investmentExists(investmentId) 
        nonReentrant
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        require(
            InvestmentManager.canDepositYield(InvestmentManager.Status(uint8(inv.status))),
            "LocalDAO: Investment is not active"
        );
        require(yieldAmount > 0, "LocalDAO: Yield amount must be greater than zero");
        require(
            IERC20(usdcAddress).balanceOf(msg.sender) >= yieldAmount,
            "LocalDAO: Insufficient USDC balance"
        );
        require(
            IERC20(usdcAddress).allowance(msg.sender, address(this)) >= yieldAmount,
            "LocalDAO: Insufficient USDC allowance"
        );

        IERC20(usdcAddress).safeTransferFrom(msg.sender, address(this), yieldAmount);
        
        inv.totalYieldGenerated += yieldAmount;
        
        YieldDistribution storage dist = yieldDistributions[investmentId];
        dist.investmentId = investmentId;
        dist.totalAmount += yieldAmount;
        dist.remainingAmount += yieldAmount;
        dist.expenseReportCID = expenseReportCID;
        dist.timestamp = block.timestamp;

        _addActivity(
            investmentId,
            "yield_deposited",
            string(abi.encodePacked("Yield deposited: ", _uintToString(yieldAmount))),
            expenseReportCID
        );

        emit YieldDeposited(investmentId, yieldAmount, expenseReportCID, block.timestamp);
    }

    /**
     * @notice Claim yield from an active investment
     * @dev Can be called by anyone who staked (upvoted), even if they're no longer a member
     * @dev Yield is distributed proportionally based on stake amount
     * @param investmentId ID of the active investment
     */
    function claimYield(uint256 investmentId)
        external
        investmentExists(investmentId)
        hasStakeInInvestment(investmentId)
        nonReentrant
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        require(inv.status == Status.ACTIVE, "LocalDAO: Investment is not active");

        Vote storage userVote = votes[investmentId][msg.sender];
        require(!userVote.hasClaimedYield, "LocalDAO: Yield already claimed");

        uint256 claimable = YieldCalculator.calculateUserYield(
            userVote.numberOfVotes,
            inv.upvotes,
            inv.totalYieldGenerated
        );

        require(claimable > 0, "LocalDAO: No yield available to claim");
        require(
            YieldCalculator.validateDistribution(
                inv.totalYieldDistributed,
                claimable,
                inv.totalYieldGenerated
            ),
            "LocalDAO: Distribution would exceed total yield"
        );

        userVote.hasClaimedYield = true;
        userVote.yieldClaimed = claimable;
        inv.totalYieldDistributed += claimable;

        YieldDistribution storage dist = yieldDistributions[investmentId];
        dist.distributedAmount += claimable;
        dist.remainingAmount -= claimable;

        IERC20(usdcAddress).safeTransfer(msg.sender, claimable);

        emit YieldClaimed(investmentId, msg.sender, claimable, block.timestamp);
    }

    function calculateClaimableYield(
        uint256 investmentId,
        address voter
    ) 
        external 
        view 
        investmentExists(investmentId)
        returns (uint256 claimableAmount) 
    {
        Investment memory inv = investments[investmentId];
        if (inv.status != Status.ACTIVE) {
            return 0;
        }

        Vote memory userVote = votes[investmentId][voter];
        if (userVote.numberOfVotes == 0 || userVote.voteValue != 1 || userVote.hasClaimedYield) {
            return 0;
        }

        return YieldCalculator.calculateUserYield(
            userVote.numberOfVotes,
            inv.upvotes,
            inv.totalYieldGenerated
        );
    }

    function getYieldDistribution(uint256 investmentId)
        external
        view
        investmentExists(investmentId)
        returns (YieldDistribution memory)
    {
        return yieldDistributions[investmentId];
    }

    // ===== INVESTMENT CLOSURE =====
    /**
     * @notice Close an investment after all yield is distributed
     * @dev Only admins can close. Requires all yield to be distributed
     * @param investmentId ID of the investment to close
     */
    function closeInvestment(uint256 investmentId)
        external
        onlyAdmin
        investmentExists(investmentId)
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        require(
            InvestmentManager.canCloseInvestment(
                InvestmentManager.Status(uint8(inv.status)),
                inv.totalYieldGenerated,
                inv.totalYieldDistributed
            ),
            "LocalDAO: Investment cannot be closed (check status and yield distribution)"
        );
        require(activeInvestmentCount > 0, "LocalDAO: No active investments to close");

        inv.status = Status.ENDED;
        activeInvestmentCount--;

        _addActivity(
            investmentId,
            "investment_closed",
            "Investment closed after yield distribution",
            ""
        );

        emit InvestmentClosed(investmentId, block.timestamp);
    }

    /**
     * @notice Recover unclaimed yield after grace period
     * @dev Only creator/admin can call. Requires investment to be ENDED and grace period passed
     * @dev Off-chain: Admin should notify all stakeholders before recovery
     * @param investmentId ID of the ended investment
     * @param recipient Address to receive unclaimed yield (typically DAO treasury)
     */
    function sweepUnclaimedYield(
        uint256 investmentId,
        address recipient
    )
        external
        onlyAdmin
        investmentExists(investmentId)
        nonReentrant
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        require(inv.status == Status.ENDED, "LocalDAO: Investment must be ended");
        require(recipient != address(0), "LocalDAO: Invalid recipient address");
        
        YieldDistribution storage dist = yieldDistributions[investmentId];
        require(dist.remainingAmount > 0, "LocalDAO: No unclaimed yield to recover");
        
        // Check if grace period has passed since last yield deposit or investment closure
        uint256 gracePeriodEnd = dist.timestamp + GRACE_PERIOD_FOR_UNCLAIMED_YIELD;
        require(block.timestamp >= gracePeriodEnd, "LocalDAO: Grace period not yet expired");

        uint256 unclaimedAmount = dist.remainingAmount;
        dist.remainingAmount = 0;
        dist.distributedAmount += unclaimedAmount; // Mark as distributed for accounting

        IERC20(usdcAddress).safeTransfer(recipient, unclaimedAmount);

        _addActivity(
            investmentId,
            "yield_recovered",
            string(abi.encodePacked("Unclaimed yield recovered: ", _uintToString(unclaimedAmount))),
            ""
        );

        emit UnclaimedYieldRecovered(investmentId, recipient, unclaimedAmount, block.timestamp);
    }

    // ===== ACTIVITY TIMELINE =====
    function _addActivity(
        uint256 investmentId,
        string memory eventType,
        string memory details,
        string memory documentCID
    ) internal {
        investmentTimeline[investmentId].push(Activity({
            eventType: eventType,
            timestamp: block.timestamp,
            details: details,
            documentCID: documentCID,
            actor: msg.sender
        }));

        emit ActivityLogged(investmentId, eventType, details, block.timestamp);
    }

    function getInvestmentTimeline(uint256 investmentId)
        external
        view
        investmentExists(investmentId)
        returns (Activity[] memory)
    {
        return investmentTimeline[investmentId];
    }

    // ===== ADMIN FUNCTIONS =====
    /**
     * @notice Add a new admin to the DAO
     * @dev Only creator can add admins. Admins have significant powers - use with caution
     * @dev Off-chain: Creator should verify admin identity and trustworthiness before adding
     * @param admin Address of the new admin
     */
    function addAdmin(address admin) external onlyCreator {
        require(admin != address(0), "LocalDAO: Invalid admin address");
        require(!isAdmin[admin], "LocalDAO: Address is already an admin");

        isAdmin[admin] = true;
        admins.push(admin);

        emit AdminAdded(admin);
    }

    /**
     * @notice Remove an admin from the DAO
     * @dev Only creator can remove admins
     * @param admin Address of the admin to remove
     */
    function removeAdmin(address admin) external onlyCreator {
        require(isAdmin[admin], "LocalDAO: Address is not an admin");

        isAdmin[admin] = false;
        
        // Remove from array
        for (uint256 i = 0; i < admins.length; i++) {
            if (admins[i] == admin) {
                admins[i] = admins[admins.length - 1];
                admins.pop();
                break;
            }
        }

        emit AdminRemoved(admin);
    }

    /**
     * @notice Add a new finance manager to the DAO
     * @dev Only creator can add finance managers. Finance managers can deposit yield and extend deadlines
     * @dev Off-chain: Creator should verify finance manager credentials and trustworthiness
     * @param manager Address of the new finance manager
     */
    function addFinanceManager(address manager) external onlyCreator {
        require(manager != address(0), "LocalDAO: Invalid finance manager address");
        require(!isFinanceManager[manager], "LocalDAO: Address is already a finance manager");

        isFinanceManager[manager] = true;

        emit FinanceManagerAdded(manager);
    }

    /**
     * @notice Remove a finance manager from the DAO
     * @dev Only creator can remove finance managers
     * @param manager Address of the finance manager to remove
     */
    function removeFinanceManager(address manager) external onlyCreator {
        require(isFinanceManager[manager], "LocalDAO: Address is not a finance manager");

        isFinanceManager[manager] = false;

        emit FinanceManagerRemoved(manager);
    }

    /**
     * @notice Update DAO description and logo URI
     * @dev Only admins can update DAO information
     * @param newDescription New description for the DAO
     * @param newLogoURI New logo URI (IPFS CID or URL)
     */
    function updateDAOInfo(
        string memory newDescription,
        string memory newLogoURI
    ) external onlyAdmin whenNotPaused {
        require(bytes(newDescription).length > 0, "LocalDAO: Description cannot be empty");
        description = newDescription;
        logoURI = newLogoURI;
    }

    /**
     * @notice Pause all DAO operations (emergency function)
     * @dev Only creator can pause. Prevents all state-changing operations
     */
    function pause() external onlyCreator {
        _pause();
        emit DAOPaused(block.timestamp);
    }

    /**
     * @notice Unpause DAO operations
     * @dev Only creator can unpause
     */
    function unpause() external onlyCreator {
        _unpause();
        emit DAOUnpaused(block.timestamp);
    }

    // ===== HELPER FUNCTIONS =====
    function _addressToString(address addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3+i*2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ===== EVENTS =====
    event MemberAdded(address indexed member, uint256 timestamp);
    event MemberKYCVerified(address indexed member, uint256 timestamp);
    event MemberRemoved(address indexed member, uint256 timestamp);
    event MemberExited(address indexed member, uint256 timestamp);

    event InvestmentCreated(
        uint256 indexed investmentId,
        string name,
        uint256 fundNeeded,
        Grade grade,
        uint256 deadline
    );
    event InvestmentActivated(uint256 indexed investmentId, uint256 timestamp);
    event InvestmentClosed(uint256 indexed investmentId, uint256 timestamp);
    event InvestmentIncomplete(uint256 indexed investmentId, uint256 timestamp);
    event DeadlineExtended(
        uint256 indexed investmentId,
        uint256 newDeadline,
        uint256 extensionCount
    );

    event VoteCast(
        uint256 indexed investmentId,
        address indexed voter,
        uint256 numberOfVotes,
        uint8 voteValue,
        uint256 timestamp
    );
    event StakeWithdrawn(
        uint256 indexed investmentId,
        address indexed voter,
        uint256 amount
    );

    event YieldDeposited(
        uint256 indexed investmentId,
        uint256 amount,
        string expenseReportCID,
        uint256 timestamp
    );
    event YieldClaimed(
        uint256 indexed investmentId,
        address indexed voter,
        uint256 amount,
        uint256 timestamp
    );

    event ActivityLogged(
        uint256 indexed investmentId,
        string eventType,
        string details,
        uint256 timestamp
    );

    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event FinanceManagerAdded(address indexed manager);
    event FinanceManagerRemoved(address indexed manager);
    event DAOPaused(uint256 timestamp);
    event DAOUnpaused(uint256 timestamp);
    event UnclaimedYieldRecovered(
        uint256 indexed investmentId,
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );
}

