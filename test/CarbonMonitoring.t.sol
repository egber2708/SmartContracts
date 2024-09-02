// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/CarbonMonitoring.sol";
import "../src/GreenEmissionsNFT.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {
        _mint(msg.sender, 1000000 * 10**6); // 1,000,000 USDC for testing
    }
}


contract CarbonMonitoringTest is Test {

    CarbonMonitoring public project;
    GreenEmissionsNFT public nftContract;
    MockUSDC public usdcToken;


    address public admin = address(0x1);
    address public admin_green = address(0x2);
    address public farmer = address(0x3);
    address[] public buyerAddresses;
    uint256[] public co2TokensBought;
    uint256[] public usdcContributed;
    uint256 public projectId = 1;
    string public projectName = "Test Project";
    uint256 public co2BindingAmount = 1500; // USDC has 6 decimals
    uint256 public startDate = block.timestamp;
    uint256 public endDate = block.timestamp + 30 days;
    uint256 public pricePerTon = 10 * 10**6; // 10 USDC per ton

    function setUp() public {
       
       // Populate dynamic arrays with example data
        buyerAddresses.push(address(0x5));
        buyerAddresses.push(address(0x6));
        buyerAddresses.push(address(0x7));
        co2TokensBought.push(500);
        co2TokensBought.push(500);
        co2TokensBought.push(500);
        usdcContributed.push(5000 * 10**6); // 5000 USDC in smallest unit
        usdcContributed.push(5000 * 10**6); // 5000 USDC in smallest unit
        usdcContributed.push(5000 * 10**6); // 5000 USDC in smallest unit
        nftContract = new GreenEmissionsNFT();
        
        vm.prank(admin);
        usdcToken = new MockUSDC();


         // Provide initial balances
        vm.deal(admin, 100 ether); 
        vm.deal(farmer, 100 ether);
        vm.deal(buyerAddresses[0], 10 ether); // Simulate balance for buyer 1
        vm.deal(buyerAddresses[1], 10 ether); // Simulate balance for buyer 2

        // Deploy the CarbonMonitoring contract
        vm.prank(admin); // Simulate admin deployment
        project = new CarbonMonitoring(
            projectId,
            projectName,
            co2BindingAmount,
            admin_green,
            buyerAddresses,
            co2TokensBought,
            usdcContributed,
            startDate,
            endDate,
            pricePerTon,
            address(nftContract),
            farmer,
            address(usdcToken)
        );

        // Fund the contract with USDC
        vm.prank(admin);
        usdcToken.approve(address(project), 15000 * 10**6);
        vm.prank(admin);
        usdcToken.transfer(address(project), 15000 * 10**6); // Transfer 1000 USDC to contract
    }


    function testGenerateCarbonCredits() public {
        vm.prank(admin);
        project.generateCarbonCredits(500);
        (, , , uint256 co2Generated) = project.getProjectDetails();
        assertEq(co2Generated, 500, "CO2 generated should be 500");
    }


    function testCheckContractStatusActive() public {
        vm.prank(admin);
        project.generateCarbonCredits(400); // Simulate generating the required CO2
        
        vm.prank(admin);
        project.checkContractStatus();
        assertEq(uint256(project.getContractStatus()),uint256(CarbonMonitoring.ContractStatus.Active), "Contract should be active.");
        
        vm.prank(admin);
        project.generateCarbonCredits(1200); // Simulate generating the required CO2
        assertEq(uint256(project.getContractStatus()),uint256(CarbonMonitoring.ContractStatus.Closed), "Contract should be closed.");
    }



    function testCompleteTransaction() public {
        assertEq(usdcToken.balanceOf(farmer), 0, 'The Farmer Balance should be empty'); // All USDC should be transferred to farmer
        vm.prank(admin);
        project.generateCarbonCredits(1500); // Complete the CO2 generation
        assertEq(uint256(project.getContractStatus()), uint256(CarbonMonitoring.ContractStatus.Closed), "Contract should be closed.");
        assertEq(usdcToken.balanceOf(farmer), 15000 * 10**6); // All USDC should be transferred to farmer
    }


    function FailtestCompleteTransaction() public {
        vm.prank(admin);
        project.generateCarbonCredits(15000); // Complete the CO2 generation
        vm.prank(admin);
        project.generateCarbonCredits(1000); // Complete the CO2 generation
    }


    function testPartialTransaction() public {
        vm.prank(admin);
        project.generateCarbonCredits(750); // Only generate half of the required CO2
        vm.warp(endDate + 2); // Move forward to after the end date

        vm.prank(admin);
        project.checkContractStatus();
        assertEq(uint256(project.getContractStatus()), uint256(CarbonMonitoring.ContractStatus.Closed), "Contract should be closed after partial transaction.");
   

        assertEq(usdcToken.balanceOf(buyerAddresses[0]), 2500 * 10**6); // 50% refund
        assertEq(usdcToken.balanceOf(buyerAddresses[1]), 2500 * 10**6); // 50% refund
        assertEq(usdcToken.balanceOf(buyerAddresses[2]), 2500 * 10**6); // 50% refund
   
    }

    function testCancelContract() public {
        vm.prank(admin);
        project.cancelContract();
        assertEq(uint256(project.getContractStatus()), uint256(CarbonMonitoring.ContractStatus.Cancelled), "Contract should be cancelled.");
    // Verify refunds to buyers
        assertEq(usdcToken.balanceOf(buyerAddresses[0]), 4950 * 10**6); // 99% refund after 1% fee
        assertEq(usdcToken.balanceOf(buyerAddresses[1]), 4950 * 10**6); // 99% refund after 1% fee
        assertEq(usdcToken.balanceOf(buyerAddresses[2]), 4950 * 10**6); // 99% refund after 1% fee
    
    }

 
    function testCollectRemainingUSDC() public {
        vm.prank(admin);
        project.generateCarbonCredits(1000);
        
        vm.prank(admin);
        project.cancelContract(); // Cancel the contract first
        
        vm.prank(admin_green);
        project.collectRemainingUSDC(); // Verify remaining USDC is collected by admin_green
        assertEq(usdcToken.balanceOf(admin_green), 150 * 10**6);
    }

}
