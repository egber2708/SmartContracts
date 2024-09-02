// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../src/CarbonCrowFunding.sol";

// Mock USDC Token for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {
        _mint(msg.sender, 1000000 * 10**6); // 1,000,000 USDC for testing  
    }
}

// Test Contract for CarbonCrowdfunding
contract CarbonCrowdfundingTest is Test {

    
    CarbonCrowdfunding public carbonCrowdfunding;
    MockUSDC public usdcToken;

    address public admin = address(0x1);
    address public greenWallet = address(0x2);
    address public farmer = address(0x3);
    address[] public buyerAddresses;
    uint256 public projectId;

    function setUp() public {
        
        // Deploy mock USDC token
        usdcToken = new MockUSDC();

        // Deploy CarbonCrowdfunding contract
        vm.prank(admin);
        carbonCrowdfunding = new CarbonCrowdfunding(address(usdcToken));

        // Authorize the farmer
        vm.prank(admin);
        carbonCrowdfunding.authorizeFarmer(farmer);

        // Create a project
        vm.prank(admin);
        projectId = carbonCrowdfunding.createProject(
            "project_001",
            "Carbon Project 1",
            block.timestamp + 1 days,
            block.timestamp + 30 days,
            10 * 10**6, // 10 USDC per ton
            1000,
            farmer
        );

        // Provide initial balances
        vm.deal(admin, 100 ether); 

        // Fund buyers with USDC and approve CarbonCrowdfunding contract
        buyerAddresses = [address(0x4), address(0x5), address(0x6)];
        uint256 amountToApprove = 100 * 10**6;

        for (uint256 i = 0; i < buyerAddresses.length; i++) {

            usdcToken.transfer(buyerAddresses[i], amountToApprove);
            
            vm.deal(buyerAddresses[i], 2 ether); // Simulate balance for buyer 1
            vm.prank(buyerAddresses[i]);
            usdcToken.approve(address(carbonCrowdfunding), amountToApprove);
        }
    }

    
    function testCreateProject() public {
        (
            uint256 id,
            string memory id_db,
            string memory name,
            uint256 startDate,
            uint256 endDate,
            uint256 pricePerTon,
            uint256 estimatedCO2Binding,
            address farmerWallet,
            CarbonCrowdfunding.ProjectStatus status,
            uint256 totalSold
        ) = carbonCrowdfunding.getProjectDetails(projectId);

        console.log('the value is', id);

        assertEq(id, projectId);
        assertEq(id_db, "project_001");
        assertEq(name, "Carbon Project 1");
        assertEq(pricePerTon, 10 * 10**6);
        assertEq(estimatedCO2Binding, 1000);
        assertEq(farmerWallet, farmer);
        assertEq(uint(status), uint(CarbonCrowdfunding.ProjectStatus.Active));
        assertEq(totalSold, 0);
    }

    function testParticipateInProject() public {
        uint256 amount = 10; // 50 tons of CO2Binding

        // Participate in the project as buyer 0x4
        vm.prank(buyerAddresses[0]);
        carbonCrowdfunding.participateInProject{value: 100 * 10**6}(projectId, amount);

        // Check the project details after participation
        (
            uint256 id,
            string memory id_db,
            string memory name,
            uint256 startDate,
            uint256 endDate,
            uint256 pricePerTon,
            uint256 estimatedCO2Binding,
            address farmerWallet,
            CarbonCrowdfunding.ProjectStatus status,
            uint256 totalSold
        ) = carbonCrowdfunding.getProjectDetails(projectId);

        assertEq(totalSold, 10);

        // Check buyer's contribution
        address[] memory buyers = carbonCrowdfunding.getBuyersForProject(projectId);
        assertEq(buyers[0], buyerAddresses[0]);
    }


    function testCancelProject() public {
        uint256 amount = 10; // 50 tons of CO2Binding

        // Participate in the project as buyer 0x4
        vm.prank(buyerAddresses[1]);
        carbonCrowdfunding.participateInProject{value: 10 * 10**6}(projectId, amount);

        // Cancel the project
        vm.prank(admin);
        carbonCrowdfunding.cancelProject(projectId);

        // Check the project status
        (
            uint256 id,
            string memory id_db,
            string memory name,
            uint256 startDate,
            uint256 endDate,
            uint256 pricePerTon,
            uint256 estimatedCO2Binding,
            address farmerWallet,
            CarbonCrowdfunding.ProjectStatus status,
            uint256 totalSold
        ) = carbonCrowdfunding.getProjectDetails(projectId);

        assertEq(uint(status), uint(CarbonCrowdfunding.ProjectStatus.Cancelled));

        // Verify buyer received refund (minus fees)
        uint256 buyerBalance = usdcToken.balanceOf(buyerAddresses[0]);
        uint256 expectedRefund = (50 * 10**6) - (50 * 10**6 * carbonCrowdfunding.transferFee() / 1000);
        assertEq(buyerBalance, expectedRefund);
    }

    function testValidateProjects() public {
        // Fast forward to a date where the project should be validated
        vm.warp(block.timestamp + 2 days);

        // Validate projects
        vm.prank(admin);
        uint256[] memory validProjectIds = carbonCrowdfunding.validateProjects();

        // Check that the project is valid
        assertEq(validProjectIds[0], projectId);
    }

    function testExecuteProject() public {
        uint256 amount = 100; // 1000 tons of CO2Binding

        // Participate in the project as buyer 0x4
        vm.prank(buyerAddresses[0]);
        carbonCrowdfunding.participateInProject{value: 100 * 10**6}(projectId, amount);

        // Fast forward to the project's start date
        vm.warp(block.timestamp + 2 days);

        // Execute the project
        vm.prank(admin);
        carbonCrowdfunding.executeProject(projectId);

        // Check the project status
        (
            uint256 id,
            string memory id_db,
            string memory name,
            uint256 startDate,
            uint256 endDate,
            uint256 pricePerTon,
            uint256 estimatedCO2Binding,
            address farmerWallet,
            CarbonCrowdfunding.ProjectStatus status,
            uint256 totalSold
        ) = carbonCrowdfunding.getProjectDetails(projectId);

        assertEq(uint(status), uint(CarbonCrowdfunding.ProjectStatus.Executed));

        // Check that the USDC was transferred to the CarbonMonitoring contract
        CarbonMonitoring newProjectContract = carbonCrowdfunding.carbonMonitoring();
        uint256 contractBalance = newProjectContract.getUSDCBalance();
        assertEq(contractBalance, 1000 * 10**6);
    }
}
