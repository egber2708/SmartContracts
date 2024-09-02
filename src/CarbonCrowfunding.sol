// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "forge-std/console.sol";
import './CarbonMonitoring.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CarbonCrowdfunding {

    address public admin;
    address public greenWallet;
    uint256 public transferFee = 10; 
    IERC20 public  usdcGreenToken;


    CarbonMonitoring  public carbonMonitoring;

    enum ProjectStatus { Active, Completed, Cancelled, Executed }

    struct Project {
        uint256 id;
        string id_db;
        string name;
        uint256 startDate;
        uint256 endDate;
        uint256 pricePerTon;
        uint256 estimatedCO2Binding;
        uint256 totalSold;
        address payable farmerWallet;
        ProjectStatus status;
        mapping(address => uint256) buyersContribution;
        mapping(address => uint256) buyersCO2Binding;
        address[] buyers;
    }

    mapping(uint256 => Project) public projects;
    mapping(address => bool) public authorizedFarmers;
    uint256 public projectCount;
    uint256[] public cancelledProjects;
    uint256[] public completedProjects;
    uint256[] public executedProjects;

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action.");
        _;
    }

    modifier onlyAuthorizedFarmer() {
        require(authorizedFarmers[msg.sender], "You are not authorized to create projects.");
        _;
    }

    modifier projectExists(uint256 _projectId) {
        require(projects[_projectId].id == _projectId, "Project does not exist.");
        _;
    }

    constructor(
         address _usdcTokenAddress
     ) {
        admin = msg.sender;
        usdcGreenToken = IERC20(_usdcTokenAddress);
    }

    function authorizeFarmer(address _farmer) external onlyAdmin {
        authorizedFarmers[_farmer] = true;
    }

    function deauthorizeFarmer(address _farmer) external onlyAdmin {
        authorizedFarmers[_farmer] = false;
    }

    function createProject(
        string memory _id_db,
        string memory _name,
        uint256 _startDate,
        uint256 _endDate,
        uint256 _pricePerTon,
        uint256 _estimatedCO2Binding,
        address _farmer
    ) external onlyAdmin returns (uint256) {
        require(_startDate > block.timestamp, "Start date must be in the future.");
        require(_endDate > _startDate, "End date must be after start date.");
        projectCount++;
        Project storage newProject = projects[projectCount];
        newProject.id = projectCount;
        newProject.id_db = _id_db;
        newProject.name = _name;
        newProject.startDate = _startDate;
        newProject.endDate = _endDate;
        newProject.pricePerTon = _pricePerTon;
        newProject.estimatedCO2Binding = _estimatedCO2Binding;
        newProject.farmerWallet = payable(_farmer);
        newProject.status = ProjectStatus.Active;
        return projectCount;
    }

    function participateInProject(uint256 _projectId, uint256 _amount) external payable projectExists(_projectId) {
        Project storage project = projects[_projectId];
        require(block.timestamp < project.startDate, "Project has already started.");
        require(project.status == ProjectStatus.Active, "Project is not active.");
        require(_amount <= project.estimatedCO2Binding - project.totalSold, "Not enough CO2Binding left.");

        uint256 totalCost = _amount * project.pricePerTon;
        require(usdcGreenToken.transferFrom(msg.sender, address(this), totalCost), "USDC transfer failed.");

        require(msg.value >= totalCost, "Insufficient payment.");

        project.buyersContribution[msg.sender] += totalCost;
        project.buyersCO2Binding[msg.sender] += _amount;
        project.totalSold += _amount;
        project.buyers.push(msg.sender);

        // If fully sold out, mark as completed
        if (project.totalSold >= project.estimatedCO2Binding) {
            project.status = ProjectStatus.Completed;
            completedProjects.push(_projectId);
        }
    }

    function cancelProject(uint256 _projectId) external projectExists(_projectId) {
        Project storage project = projects[_projectId];
        require(msg.sender == project.farmerWallet || msg.sender == admin, "Only the farmer or admin can cancel the project.");
        require(project.status == ProjectStatus.Active, "Project is not active.");

        project.status = ProjectStatus.Cancelled;
        cancelledProjects.push(_projectId);

        // Refund buyers
        for (uint256 i = 0; i < project.buyers.length; i++) {
            address buyer = project.buyers[i];
            uint256 refundAmount = project.buyersContribution[buyer] - (project.buyersContribution[buyer] * transferFee / 1000);
            payable(buyer).transfer(refundAmount);
        }
    }

    function validateProjects() external view returns (uint256[] memory) {
        require(msg.sender == admin || msg.sender == greenWallet, "Only admin or green wallet can validate projects.");
        uint256 count = 0;

        for (uint256 i = 1; i <= projectCount; i++) {
            if (projects[i].status == ProjectStatus.Active && projects[i].startDate <= block.timestamp) {
                count++;
            }
        }

        uint256[] memory validProjectIds = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 1; i <= projectCount; i++) {
            if (projects[i].status == ProjectStatus.Active && projects[i].startDate <= block.timestamp) {
                validProjectIds[index] = projects[i].id;
                index++;
            }
        }

        return validProjectIds;
    }

    function executeProject(uint256 _projectId) external projectExists(_projectId) {
        require(msg.sender == admin || msg.sender == greenWallet, "Only admin or green wallet can execute projects.");
        Project storage project = projects[_projectId];
        require(block.timestamp >= project.startDate || project.status == ProjectStatus.Completed, "Project cannot be executed yet.");
        
        // Create CarbonMonitoring contract
        address[] memory buyers = project.buyers;
        uint256[] memory co2TokensBought = new uint256[](buyers.length);
        uint256[] memory usdcContributed = new uint256[](buyers.length);

        for (uint256 i = 0; i < buyers.length; i++) {
            co2TokensBought[i] = project.buyersCO2Binding[buyers[i]];
            usdcContributed[i] = project.buyersContribution[buyers[i]];
        }

        CarbonMonitoring newProjectContract = new CarbonMonitoring(
            project.id,
            project.name,
            project.estimatedCO2Binding,
            greenWallet,
            buyers,
            co2TokensBought,
            usdcContributed,
            project.startDate,
            project.endDate,
            project.pricePerTon,
            address(this),  // Assuming the NFT contract is this same contract for simplicity
            project.farmerWallet,
            address(usdcGreenToken)
            );

        // Transfer USDC to the new contract
        uint256 totalUSDC = usdcGreenToken.balanceOf(address(this)) ;
        require(totalUSDC >= project.totalSold, "No USDC to transfer.");
        
        newProjectContract.depositUSDC(project.totalSold);

        // Mark project as Executed
        project.status = ProjectStatus.Executed;
        executedProjects.push(_projectId);
    }

    function getProjectDetails(uint256 _projectId) external view returns (
        uint256,
        string memory,
        string memory,
        uint256,
        uint256,
        uint256,
        uint256,
        address,
        ProjectStatus,
        uint256
    ) {
        Project storage project = projects[_projectId];
        return (
            project.id,
            project.id_db,
            project.name,
            project.startDate,
            project.endDate,
            project.pricePerTon,
            project.estimatedCO2Binding,
            project.farmerWallet,
            project.status,
            project.totalSold
        );
    }

    function getBuyersForProject(uint256 _projectId) external view projectExists(_projectId) returns (address[] memory) {
        return projects[_projectId].buyers;
    }

    function getCancelledProjects() external view returns (uint256[] memory) {
        return cancelledProjects;
    }

    function getCompletedProjects() external view returns (uint256[] memory) {
        return completedProjects;
    }

    function getExecuteddProjects() external view returns (uint256[] memory) {
        return executedProjects;
    }

}
