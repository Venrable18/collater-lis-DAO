// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LocalDAO} from "../src/LocalDAO.sol";
import {LocalDAOFactory} from "../src/LocalDAOFactory.sol";
import {ILocalDAO} from "../src/interfaces/ILocalDAO.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LocalDAOTest is Test {
    LocalDAO public dao;
    LocalDAOFactory public factory;
    MockUSDC public usdc;
    
    address public creator;
    address public admin;
    address public financeManager;
    address public member1;
    address public member2;
    address public member3;
    address public nonMember;

    uint256 constant INITIAL_USDC = 1000000 * 1e6; // 1M USDC with 6 decimals

    function setUp() public {
        creator = address(0x1);
        admin = address(0x2);
        financeManager = address(0x3);
        member1 = address(0x4);
        member2 = address(0x5);
        member3 = address(0x6);
        nonMember = address(0x7);

        // Deploy USDC
        usdc = new MockUSDC();

        // Deploy Factory
        vm.prank(creator);
        factory = new LocalDAOFactory(creator);

        // Create DAO
        vm.prank(creator);
        address daoAddress = factory.createDAO(
            "Test DAO",
            "Test Description",
            "Test Location",
            "0,0",
            "12345",
            100,
            address(usdc)
        );

        dao = LocalDAO(daoAddress);

        // Setup roles
        vm.prank(creator);
        dao.addAdmin(admin);

        vm.prank(creator);
        dao.addFinanceManager(financeManager);

        // Add members
        vm.prank(admin);
        dao.addMember(member1, keccak256("kyc1"));

        vm.prank(admin);
        dao.addMember(member2, keccak256("kyc2"));

        vm.prank(admin);
        dao.addMember(member3, keccak256("kyc3"));

        // Mint USDC to members
        usdc.mint(member1, INITIAL_USDC);
        usdc.mint(member2, INITIAL_USDC);
        usdc.mint(member3, INITIAL_USDC);
        usdc.mint(financeManager, INITIAL_USDC);
    }

    // ===== MEMBER MANAGEMENT TESTS =====
    function test_AddMember() public {
        address newMember = address(0x8);
        bytes32 kycHash = keccak256("kyc4");

        vm.prank(admin);
        dao.addMember(newMember, kycHash);

        (, bool kycVerified, , , bool isActive) = dao.members(newMember);
        assertTrue(isActive);
        assertTrue(kycVerified);
        assertEq(dao.memberCount(), 4);
    }

    function test_AddMember_OnlyAdmin() public {
        vm.prank(nonMember);
        vm.expectRevert("Not admin");
        dao.addMember(address(0x8), keccak256("kyc"));
    }

    function test_AddMember_MaxMembership() public {
        // We already have 3 members, so fill up to max membership (100)
        // Start from a higher address to avoid conflicts
        vm.startPrank(admin);
        for (uint256 i = 10; i <= 106; i++) {
            address newMember = address(uint160(i));
            dao.addMember(newMember, keccak256(abi.encodePacked("kyc", i)));
            if (dao.memberCount() >= 100) break; // Stop when we reach max
        }
        vm.stopPrank();

        // Verify we're at max
        assertEq(dao.memberCount(), 100);

        // Try to add one more
        vm.prank(admin);
        vm.expectRevert("LocalDAO: Maximum membership limit reached");
        dao.addMember(address(0x999), keccak256("kyc"));
    }

    function test_RemoveMember() public {
        vm.prank(admin);
        dao.removeMember(member1);

        (, , , , bool isActive) = dao.members(member1);
        assertFalse(isActive);
        assertEq(dao.memberCount(), 2);
    }

    function test_ExitDAO() public {
        vm.prank(member1);
        dao.exitDAO();

        (, , , , bool isActive) = dao.members(member1);
        assertFalse(isActive);
        assertEq(dao.memberCount(), 2);
    }

    // ===== INVESTMENT CREATION TESTS =====
    function test_CreateInvestment() public {
        string[] memory docs = new string[](1);
        docs[0] = "QmHash1";

        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6, // 10k USDC
            5, // 5% yield
            ILocalDAO.Grade.A,
            30, // 30 days
            docs
        );

        assertEq(investmentId, 1);
        LocalDAO.Investment memory inv = dao.getInvestment(investmentId);
        assertEq(inv.name, "Test Investment");
        assertEq(uint8(inv.status), uint8(ILocalDAO.Status.PENDING));
        assertEq(inv.fundNeeded, 10000 * 1e6);
    }

    function test_CreateInvestment_OnlyAdmin() public {
        vm.prank(member1);
        vm.expectRevert("Not admin");
        dao.createInvestment(
            "Test",
            ILocalDAO.Category.HEALTH,
            1000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );
    }

    function test_CreateInvestment_InvalidParams() public {
        vm.prank(admin);
        vm.expectRevert("LocalDAO: Invalid investment parameters");
        dao.createInvestment(
            "Test",
            ILocalDAO.Category.HEALTH,
            0, // Invalid: fundNeeded = 0
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );
    }

    // ===== VOTING TESTS =====
    function test_Vote_Upvote() public {
        // Create investment
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        // Approve and vote
        vm.startPrank(member1);
        usdc.approve(address(dao), 5000 * 1e6);
        dao.vote(investmentId, 5000 * 1e6, 1); // Upvote with 5k USDC
        vm.stopPrank();

        LocalDAO.Vote memory vote = dao.getVote(investmentId, member1);
        assertEq(vote.numberOfVotes, 5000 * 1e6);
        assertEq(vote.voteValue, 1);
        assertEq(usdc.balanceOf(address(dao)), 5000 * 1e6);
    }

    function test_Vote_Downvote() public {
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        vm.prank(member1);
        dao.vote(investmentId, 0, 0); // Downvote

        LocalDAO.Vote memory vote = dao.getVote(investmentId, member1);
        assertEq(vote.numberOfVotes, 0);
        assertEq(vote.voteValue, 0);
        
        (uint256 upvotes, uint256 downvotes) = dao.getVoteCounts(investmentId);
        assertEq(upvotes, 0);
        assertEq(downvotes, 1);
    }

    function test_Vote_OnlyVerifiedMember() public {
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        vm.prank(nonMember);
        vm.expectRevert("Not active member");
        dao.vote(investmentId, 1000 * 1e6, 1);
    }

    function test_Vote_DeadlinePassed() public {
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            1, // 1 day deadline
            new string[](0)
        );

        // Fast forward time
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(member1);
        usdc.approve(address(dao), 1000 * 1e6);
        vm.expectRevert("LocalDAO: Voting deadline has passed");
        dao.vote(investmentId, 1000 * 1e6, 1);
        vm.stopPrank();
    }

    // ===== INVESTMENT ACTIVATION TESTS =====
    function test_ActivateInvestment() public {
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        // Members vote to reach funding goal
        vm.startPrank(member1);
        usdc.approve(address(dao), 5000 * 1e6);
        dao.vote(investmentId, 5000 * 1e6, 1);
        vm.stopPrank();

        vm.startPrank(member2);
        usdc.approve(address(dao), 5000 * 1e6);
        dao.vote(investmentId, 5000 * 1e6, 1);
        vm.stopPrank();

        // Activate
        vm.prank(admin);
        dao.activateInvestment(investmentId);

        LocalDAO.Investment memory inv = dao.getInvestment(investmentId);
        assertEq(uint8(inv.status), uint8(ILocalDAO.Status.ACTIVE));
        assertEq(dao.activeInvestmentCount(), 1);
    }

    function test_ActivateInvestment_InsufficientFunds() public {
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        // Only vote with 5k (less than needed 10k)
        vm.startPrank(member1);
        usdc.approve(address(dao), 5000 * 1e6);
        dao.vote(investmentId, 5000 * 1e6, 1);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert("LocalDAO: Investment does not meet activation requirements");
        dao.activateInvestment(investmentId);
    }

    function test_MarkInvestmentIncomplete() public {
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            1, // 1 day deadline
            new string[](0)
        );

        // Vote with less than needed
        vm.startPrank(member1);
        usdc.approve(address(dao), 5000 * 1e6);
        dao.vote(investmentId, 5000 * 1e6, 1);
        vm.stopPrank();

        // Fast forward past deadline
        vm.warp(block.timestamp + 2 days);

        vm.prank(admin);
        dao.markInvestmentIncomplete(investmentId);

        LocalDAO.Investment memory inv = dao.getInvestment(investmentId);
        assertEq(uint8(inv.status), uint8(ILocalDAO.Status.INCOMPLETE));
    }

    // ===== REFUND TESTS =====
    function test_WithdrawStake() public {
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            1,
            new string[](0)
        );

        uint256 stakeAmount = 5000 * 1e6;
        vm.startPrank(member1);
        usdc.approve(address(dao), stakeAmount);
        dao.vote(investmentId, stakeAmount, 1);
        vm.stopPrank();

        // Fast forward and mark incomplete
        vm.warp(block.timestamp + 2 days);
        vm.prank(admin);
        dao.markInvestmentIncomplete(investmentId);

        // Withdraw stake
        uint256 balanceBefore = usdc.balanceOf(member1);
        vm.prank(member1);
        dao.withdrawStake(investmentId);
        uint256 balanceAfter = usdc.balanceOf(member1);

        assertEq(balanceAfter - balanceBefore, stakeAmount);
    }

    // ===== YIELD MANAGEMENT TESTS =====
    function test_DepositYield() public {
        // Create and activate investment
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        // Fund it
        vm.startPrank(member1);
        usdc.approve(address(dao), 10000 * 1e6);
        dao.vote(investmentId, 10000 * 1e6, 1);
        vm.stopPrank();

        vm.prank(admin);
        dao.activateInvestment(investmentId);

        // Deposit yield
        uint256 yieldAmount = 500 * 1e6; // 5% of 10k
        vm.startPrank(financeManager);
        usdc.approve(address(dao), yieldAmount);
        dao.depositYield(investmentId, yieldAmount, "expenseReportCID");
        vm.stopPrank();

        LocalDAO.Investment memory inv = dao.getInvestment(investmentId);
        assertEq(inv.totalYieldGenerated, yieldAmount);
    }

    function test_ClaimYield() public {
        // Setup investment
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        // Member1 stakes 10k
        vm.startPrank(member1);
        usdc.approve(address(dao), 10000 * 1e6);
        dao.vote(investmentId, 10000 * 1e6, 1);
        vm.stopPrank();

        vm.prank(admin);
        dao.activateInvestment(investmentId);

        // Deposit yield
        uint256 yieldAmount = 500 * 1e6;
        vm.startPrank(financeManager);
        usdc.approve(address(dao), yieldAmount);
        dao.depositYield(investmentId, yieldAmount, "expenseReportCID");
        vm.stopPrank();

        // Claim yield
        uint256 balanceBefore = usdc.balanceOf(member1);
        vm.prank(member1);
        dao.claimYield(investmentId);
        uint256 balanceAfter = usdc.balanceOf(member1);

        assertEq(balanceAfter - balanceBefore, yieldAmount); // Should get 100% since only one staker
    }

    function test_CalculateClaimableYield() public {
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        vm.startPrank(member1);
        usdc.approve(address(dao), 5000 * 1e6);
        dao.vote(investmentId, 5000 * 1e6, 1);
        vm.stopPrank();

        vm.startPrank(member2);
        usdc.approve(address(dao), 5000 * 1e6);
        dao.vote(investmentId, 5000 * 1e6, 1);
        vm.stopPrank();

        vm.prank(admin);
        dao.activateInvestment(investmentId);

        uint256 yieldAmount = 500 * 1e6;
        vm.startPrank(financeManager);
        usdc.approve(address(dao), yieldAmount);
        dao.depositYield(investmentId, yieldAmount, "expenseReportCID");
        vm.stopPrank();

        uint256 claimable1 = dao.calculateClaimableYield(investmentId, member1);
        uint256 claimable2 = dao.calculateClaimableYield(investmentId, member2);

        assertEq(claimable1, 250 * 1e6); // 50% of yield
        assertEq(claimable2, 250 * 1e6); // 50% of yield
    }

    // ===== DEADLINE EXTENSION TESTS =====
    function test_ExtendDeadline() public {
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A, // Grade A can extend
            30,
            new string[](0)
        );

        LocalDAO.Investment memory invBefore = dao.getInvestment(investmentId);
        uint256 originalDeadline = invBefore.deadline;

        vm.prank(financeManager);
        dao.extendDeadline(investmentId, 15); // Extend by 15 days

        LocalDAO.Investment memory invAfter = dao.getInvestment(investmentId);
        assertEq(invAfter.deadline, originalDeadline + 15 days);
        assertEq(invAfter.extensionCount, 1);
    }

    function test_ExtendDeadline_OnlyGradeAB() public {
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.C, // Grade C cannot extend
            30,
            new string[](0)
        );

        vm.prank(financeManager);
        vm.expectRevert(); // Any revert is fine, we just want to ensure it fails
        dao.extendDeadline(investmentId, 15);
    }

    // ===== ADMIN FUNCTIONS TESTS =====
    function test_AddAdmin() public {
        address newAdmin = address(0x8);
        vm.prank(creator);
        dao.addAdmin(newAdmin);

        assertTrue(dao.isAdmin(newAdmin));
    }

    function test_AddAdmin_OnlyCreator() public {
        vm.prank(admin);
        vm.expectRevert("Not creator");
        dao.addAdmin(address(0x8));
    }

    function test_AddFinanceManager() public {
        address newManager = address(0x8);
        vm.prank(creator);
        dao.addFinanceManager(newManager);

        // Check via trying to use finance manager function
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test",
            ILocalDAO.Category.HEALTH,
            1000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        vm.prank(newManager);
        dao.extendDeadline(investmentId, 10); // Should work
    }

    function test_PauseUnpause() public {
        // Create investment before pausing
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test",
            ILocalDAO.Category.HEALTH,
            1000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        vm.prank(creator);
        dao.pause();

        // Try to vote while paused
        vm.startPrank(member1);
        usdc.approve(address(dao), 1000 * 1e6);
        vm.expectRevert();
        dao.vote(investmentId, 1000 * 1e6, 1);
        vm.stopPrank();

        vm.prank(creator);
        dao.unpause();

        // Should work now
        vm.startPrank(member1);
        dao.vote(investmentId, 1000 * 1e6, 1);
        vm.stopPrank();
    }

    // ===== CLOSE INVESTMENT TESTS =====
    function test_CloseInvestment() public {
        // Setup and activate investment
        vm.prank(admin);
        uint256 investmentId = dao.createInvestment(
            "Test Investment",
            ILocalDAO.Category.HEALTH,
            10000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        vm.startPrank(member1);
        usdc.approve(address(dao), 10000 * 1e6);
        dao.vote(investmentId, 10000 * 1e6, 1);
        vm.stopPrank();

        vm.prank(admin);
        dao.activateInvestment(investmentId);

        // Deposit and claim all yield
        uint256 yieldAmount = 500 * 1e6;
        vm.startPrank(financeManager);
        usdc.approve(address(dao), yieldAmount);
        dao.depositYield(investmentId, yieldAmount, "expenseReportCID");
        vm.stopPrank();

        vm.prank(member1);
        dao.claimYield(investmentId);

        // Close investment
        vm.prank(admin);
        dao.closeInvestment(investmentId);

        LocalDAO.Investment memory inv = dao.getInvestment(investmentId);
        assertEq(uint8(inv.status), uint8(ILocalDAO.Status.ENDED));
        assertEq(dao.activeInvestmentCount(), 0);
    }

    // ===== HELPER FUNCTION TESTS =====
    function test_GetAllMembers() public view {
        address[] memory members = dao.getAllMembers();
        assertEq(members.length, 3);
    }

    function test_IsVerifiedMember() public view {
        assertTrue(dao.isVerifiedMember(member1));
        assertFalse(dao.isVerifiedMember(nonMember));
    }

    function test_GetInvestmentsByStatus() public {
        vm.prank(admin);
        dao.createInvestment(
            "Investment 1",
            ILocalDAO.Category.HEALTH,
            1000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        vm.prank(admin);
        dao.createInvestment(
            "Investment 2",
            ILocalDAO.Category.EDUCATION,
            2000 * 1e6,
            5,
            ILocalDAO.Grade.A,
            30,
            new string[](0)
        );

        LocalDAO.Investment[] memory pending = dao.getInvestmentsByStatus(ILocalDAO.Status.PENDING);
        assertEq(pending.length, 2);
    }
}
