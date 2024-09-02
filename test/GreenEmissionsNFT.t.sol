// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/GreenEmissionsNFT.sol";

contract GreenEmissionsNFTTest is Test {

    GreenEmissionsNFT public greenEmissionsNFT;

    address public owner = address(0x1);
    address public recipient = address(0x2);

    function setUp() public {
        // Deploy the contract
        vm.prank(owner); // Simulate a call from the owner
        greenEmissionsNFT = new GreenEmissionsNFT();
    }

    function testCreateNFT() public {
        // Simulate that the owner is creating an NFT
        vm.prank(owner);
        uint256 tokenId = greenEmissionsNFT.createNFT(
            recipient, 
            1, 
            "Project One", 
            100, 
            address(this)
        );

        // Check if the token exists
        assertTrue(greenEmissionsNFT._tokenExists(tokenId), "Token should exist after creation");

        // Check the token owner
        assertEq(greenEmissionsNFT.ownerOf(tokenId), recipient, "Recipient should be the owner of the token");

        // Check the project data associated with the token
        GreenEmissionsNFT.ProjectData memory projectData = greenEmissionsNFT.getProjectData(tokenId);
        assertEq(projectData.projectId, 1, "Project ID should be 1");
        assertEq(projectData.projectName, "Project One", "Project name should be 'Project One'");
        assertEq(projectData.CO2BindingAmount, 100, "CO2 Binding Amount should be 100");
        assertEq(projectData.sourceContract, address(this), "Source contract address should match");
    }

    function testSetBaseTokenURI() public {
        // Set a new base URI
        vm.prank(owner);
        greenEmissionsNFT.setBaseTokenURI("https://example.com/metadata/");

        // Create a new token
        vm.prank(owner);
        uint256 tokenId = greenEmissionsNFT.createNFT(
            recipient, 
            1, 
            "Project One", 
            100, 
            address(this)
        );

        // Check if the token URI is correct
        string memory expectedURI = "https://example.com/metadata/1.json";
        assertEq(greenEmissionsNFT.tokenURI(tokenId), expectedURI, "Token URI should be correctly formed");
    }

    
    function testTokenURINonexistentToken() public {
        // Set a new base URI
        vm.prank(owner);
        vm.expectRevert("ERC721Metadata: Query for nonexistent token");
        greenEmissionsNFT.getProjectData(9999);

    }

    function testFailCreateNFT_NotOwner() public {
        // Try to create an NFT as a non-owner
        vm.prank(recipient);
        greenEmissionsNFT.createNFT(
            recipient, 
            1, 
            "Project One", 
            100, 
            address(this)
        );
    }
}