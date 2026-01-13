// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {YieldCalculator} from "./libraries/YieldCalculator.sol";
import {InvestmentManager} from "./libraries/InvestmentManager.sol";

/**
 * @title LocalDAO
 * @notice Core DAO contract for governance, investments, and treasury management
 */
contract LocalDAO is Pausable, ReentrancyGuard {

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
    function addMember(address wallet, bytes32 kycProofHash) 
        external 
        onlyAdmin 
        whenNotPaused 
    {
        require(wallet != address(0), "Invalid address");
        require(!members[wallet].isActive, "Already a member");
        require(memberCount < maxMembership, "Max membership reached");

        members[wallet] = User({
            wallet: wallet,
            kycVerified: false,
            kycProofHash: kycProofHash,
            joinedAt: block.timestamp,
            isActive: true
        });
        memberAddresses.push(wallet);
        memberCount++;

        emit MemberAdded(wallet, block.timestamp);
    }

    function verifyMemberKYC(address wallet) external onlyAdmin whenNotPaused {
        require(members[wallet].isActive, "Not a member");
        require(!members[wallet].kycVerified, "Already verified");

        members[wallet].kycVerified = true;
        emit MemberKYCVerified(wallet, block.timestamp);
    }

    function removeMember(address wallet) external onlyAdmin whenNotPaused {
        require(members[wallet].isActive, "Not a member");

        members[wallet].isActive = false;
        memberCount--;

        emit MemberRemoved(wallet, block.timestamp);
    }

    function exitDAO() external whenNotPaused {
        require(members[msg.sender].isActive, "Not a member");
        // TODO: Check if user has locked funds in active investments
        
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
            "Invalid params"
        );

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
        require(inv.status == Status.PENDING, "Investment not pending");
        require(block.timestamp <= inv.deadline, "Deadline passed");
        require(voteValue <= 1, "Invalid vote value");
        require(votes[investmentId][msg.sender].numberOfVotes == 0, "Already voted");

        if (voteValue == 1) {
            // Upvote - requires USDC staking
            require(numberOfVotes > 0, "Upvote requires stake");
            require(IERC20(usdcAddress).balanceOf(msg.sender) >= numberOfVotes, "Insufficient balance");
            require(
                IERC20(usdcAddress).allowance(msg.sender, address(this)) >= numberOfVotes,
                "Insufficient allowance"
            );

            IERC20(usdcAddress).transferFrom(msg.sender, address(this), numberOfVotes);
            inv.upvotes += numberOfVotes;
            totalValueLocked += numberOfVotes;
        } else {
            // Downvote - no staking required
            require(numberOfVotes == 0, "Downvote requires no stake");
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
            "Cannot activate"
        );
        require(inv.status == Status.PENDING, "Not pending");

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
            "Cannot mark incomplete"
        );
        require(inv.status == Status.PENDING, "Not pending");

        inv.status = Status.INCOMPLETE;

        _addActivity(
            investmentId,
            "investment_incomplete",
            "Investment marked as incomplete",
            ""
        );

        emit InvestmentIncomplete(investmentId, block.timestamp);
    }

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
            "Cannot extend deadline"
        );

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
    function withdrawStake(uint256 investmentId)
        external
        investmentExists(investmentId)
        nonReentrant
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        require(inv.status == Status.INCOMPLETE, "Investment not incomplete");

        Vote storage userVote = votes[investmentId][msg.sender];
        require(userVote.numberOfVotes > 0, "No stake to withdraw");

        uint256 amount = userVote.numberOfVotes;
        userVote.numberOfVotes = 0;
        totalValueLocked -= amount;

        IERC20(usdcAddress).transfer(msg.sender, amount);

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
            "Investment not active"
        );
        require(yieldAmount > 0, "Invalid amount");
        require(
            IERC20(usdcAddress).balanceOf(msg.sender) >= yieldAmount,
            "Insufficient balance"
        );
        require(
            IERC20(usdcAddress).allowance(msg.sender, address(this)) >= yieldAmount,
            "Insufficient allowance"
        );

        IERC20(usdcAddress).transferFrom(msg.sender, address(this), yieldAmount);
        
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

    function claimYield(uint256 investmentId)
        external
        onlyVerifiedMember
        investmentExists(investmentId)
        nonReentrant
        whenNotPaused
    {
        Investment storage inv = investments[investmentId];
        require(inv.status == Status.ACTIVE, "Investment not active");

        Vote storage userVote = votes[investmentId][msg.sender];
        require(userVote.numberOfVotes > 0, "No stake");
        require(userVote.voteValue == 1, "Only upvoters can claim");
        require(!userVote.hasClaimedYield, "Already claimed");

        uint256 claimable = YieldCalculator.calculateUserYield(
            userVote.numberOfVotes,
            inv.upvotes,
            inv.totalYieldGenerated
        );

        require(claimable > 0, "Nothing to claim");
        require(
            YieldCalculator.validateDistribution(
                inv.totalYieldDistributed,
                claimable,
                inv.totalYieldGenerated
            ),
            "Distribution exceeds total"
        );

        userVote.hasClaimedYield = true;
        userVote.yieldClaimed = claimable;
        inv.totalYieldDistributed += claimable;

        YieldDistribution storage dist = yieldDistributions[investmentId];
        dist.distributedAmount += claimable;
        dist.remainingAmount -= claimable;

        IERC20(usdcAddress).transfer(msg.sender, claimable);

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
            "Cannot close"
        );

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
    function addAdmin(address admin) external onlyCreator {
        require(admin != address(0), "Invalid address");
        require(!isAdmin[admin], "Already admin");

        isAdmin[admin] = true;
        admins.push(admin);

        emit AdminAdded(admin);
    }

    function removeAdmin(address admin) external onlyCreator {
        require(isAdmin[admin], "Not admin");

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

    function addFinanceManager(address manager) external onlyCreator {
        require(manager != address(0), "Invalid address");
        require(!isFinanceManager[manager], "Already finance manager");

        isFinanceManager[manager] = true;

        emit FinanceManagerAdded(manager);
    }

    function removeFinanceManager(address manager) external onlyCreator {
        require(isFinanceManager[manager], "Not finance manager");

        isFinanceManager[manager] = false;

        emit FinanceManagerRemoved(manager);
    }

    function updateDAOInfo(
        string memory newDescription,
        string memory newLogoURI
    ) external onlyAdmin whenNotPaused {
        description = newDescription;
        logoURI = newLogoURI;
    }

    function pause() external onlyCreator {
        _pause();
        emit DAOPaused(block.timestamp);
    }

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
}

