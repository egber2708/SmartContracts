// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";



interface INFTContract {
    function createNFT(
        address to,
        uint256 _projectId,
        string memory _projectName,
        uint256 _CO2BindingAmount,
        address _sourceContract
    ) external;
}

contract CarbonMonitoring {

    IERC20 public usdcToken; // Instance of the USDC token
    address public admin;
    address public admin_green;
    address public farmer;
    uint256 public projectId;
    string  public projectName;
    uint256 public CO2BindingAmount;
    uint256 public CO2Generated;
    uint256 public startDate;
    uint256 public endDate;
    uint256 public pricePerTon;
    address public nftContractAddress;
    address public usdcGreenToken;

    enum ContractStatus { Active, Closed, Cancelled }

    ContractStatus public status;

    struct Buyer {
        address wallet;
        uint256 co2TokensBought;
        uint256 usdcContributed;
    }
    Buyer[] public buyers;
    mapping(address => Buyer) public buyerInfo;
    mapping(address => uint256) public failedTransactions;

    modifier onlyAdmin() {
        require(msg.sender == admin || msg.sender == admin_green, "Only an admin can perform this action");
        _;
    }



    constructor(
        uint256 _projectId,
        string memory _projectName,
        uint256 _CO2BindingAmount,
        address _admin,
        address[] memory _buyerAddresses,
        uint256[] memory _co2TokensBought,
        uint256[] memory _usdcContributed,
        uint256 _startDate,
        uint256 _endDate,
        uint256 _pricePerTon,
        address _nftContractAddress,
        address _farmer,
        address _usdcTokenAddress
    ) {
        require(_buyerAddresses.length == _co2TokensBought.length && _co2TokensBought.length == _usdcContributed.length, "Input array lengths must match.");

        admin = msg.sender;
        admin_green = _admin;
        usdcToken = IERC20(_usdcTokenAddress);
        farmer = _farmer;
        projectId = _projectId;
        projectName = _projectName;
        CO2BindingAmount = _CO2BindingAmount;
        CO2Generated = 0;
        startDate = _startDate;
        endDate = _endDate;
        pricePerTon = _pricePerTon;
        nftContractAddress = _nftContractAddress;
        status = ContractStatus.Active;

        for (uint256 i = 0; i < _buyerAddresses.length; i++) {
            buyers.push(Buyer(_buyerAddresses[i], _co2TokensBought[i], _usdcContributed[i]));
            buyerInfo[_buyerAddresses[i]] = Buyer(_buyerAddresses[i], _co2TokensBought[i], _usdcContributed[i]);
        }
    }



    event LogFailedNFTMint(address indexed buyer, uint256 amount);
    event BuyerRefundFailed(address indexed buyer, uint256 amount);
    event TransferUsdcFailed(address indexed buyer, uint256 amount, uint256 balance);
    event TransferUsdcSuccessful(address indexed buyer, uint256 amount, uint256 balance);
    event ContractClosed();
    event ContractCancelled(address indexed admin);
    event CarbonCreditsGenerated(address indexed admin, uint256 amount);
    event RemainingUSDCCollected(address indexed admin, uint256 amount);


    // Function to allow the admin to deposit USDC into the contract
    function depositUSDC(uint256 _amount) external onlyAdmin {
        require(usdcToken.transferFrom(msg.sender, address(this), _amount), "USDC transfer failed");
    }

    // function to check the USDC balance of the contract
    function getUSDCBalance() public view returns (uint256) {
        return usdcToken.balanceOf(address(this));
    }

    function completeTransaction() internal {
        require(CO2Generated >= CO2BindingAmount, "Not enough CO2 generated to complete the transaction.");

        for (uint256 i = 0; i < buyers.length; i++) {
            try INFTContract(nftContractAddress).createNFT(
                buyers[i].wallet,
                projectId,
                projectName,
                buyers[i].co2TokensBought,
                address(this)
            ) {} catch {
                failedTransactions[buyers[i].wallet] = buyers[i].co2TokensBought;
                emit LogFailedNFTMint(buyers[i].wallet, buyers[i].co2TokensBought);
            }
        }
        uint256 remainingBalance = usdcToken.balanceOf(address(this));
        paymentRefunds(farmer, remainingBalance);
    }

    function partialTransaction() internal {
        require(CO2Generated < CO2BindingAmount, "CO2 generated exceeds or meets the total required.");
        require(block.timestamp > endDate, "End date not reached yet.");

        uint256 percentGenerated = (CO2Generated * 100) / CO2BindingAmount;
        uint256 pendingTransfer = 0;

        for (uint256 i = 0; i < buyers.length; i++) {
            uint256 partialAmount = (buyers[i].co2TokensBought * percentGenerated) / 100;

            try INFTContract(nftContractAddress).createNFT(
                buyers[i].wallet,
                projectId,
                projectName,
                partialAmount,
                address(this)
            ) {} catch {
                failedTransactions[buyers[i].wallet] = partialAmount;
                emit LogFailedNFTMint(buyers[i].wallet, partialAmount);
            }

            uint256 refundAmount = (buyers[i].usdcContributed * percentGenerated) / 100;
            bool success = usdcToken.transfer(buyers[i].wallet, refundAmount);
            if (!success) {
                failedTransactions[buyers[i].wallet] += refundAmount;
                pendingTransfer += refundAmount;
                emit BuyerRefundFailed(buyers[i].wallet, refundAmount);
            }
        }

        uint256 remainingBalance = usdcToken.balanceOf(address(this)) - pendingTransfer;
        paymentRefunds(farmer, remainingBalance);
    }


    function cancelContract() external onlyAdmin {
        require(status == ContractStatus.Active, "Contract must be active to cancel.");
        status = ContractStatus.Cancelled;

        for (uint256 i = 0; i < buyers.length; i++) {
            uint256 refundAmount = buyers[i].usdcContributed - (buyers[i].usdcContributed / 100);
            bool success = usdcToken.transfer(buyers[i].wallet, refundAmount);
            require(success, "Refund transfer failed.");
        }

        emit ContractCancelled(msg.sender);
    }

    function collectRemainingUSDC() external onlyAdmin {
        require(status == ContractStatus.Closed || status == ContractStatus.Cancelled, "Contract must be closed or cancelled.");
        uint256 remainingBalance = usdcToken.balanceOf(address(this));
        require(remainingBalance > 0, "No USDC remaining to collect");
        bool success = usdcToken.transfer(admin_green, remainingBalance);
        require(success, "USDC transfer to admin failed.");

        emit RemainingUSDCCollected(msg.sender, remainingBalance);
    }

    function generateCarbonCredits(uint256 amount) external onlyAdmin {
        require(status == ContractStatus.Active, "Contract must be active.");
        CO2Generated += amount;
        verifyStatus();
        console.log("The value of x is:", CO2Generated, uint256(status) );
        emit CarbonCreditsGenerated(msg.sender, amount);
    }

    function checkContractStatus() external onlyAdmin {
        verifyStatus();
    }

    function verifyStatus() internal {
        if (CO2Generated >= CO2BindingAmount) {
            completeTransaction();
        } else if (block.timestamp > endDate) {
            partialTransaction();
        }
    }

    function paymentRefunds(address receiver, uint256 amount) internal {
        require(usdcToken.balanceOf(address(this)) >= amount, "Insufficient USDC balance to execute");
        status = ContractStatus.Closed; 

        bool transferSuccess = usdcToken.transfer(receiver, amount);
     
        if (!transferSuccess) {
            emit TransferUsdcFailed(receiver, amount, usdcToken.balanceOf(address(this)));
        } else {
            emit TransferUsdcSuccessful(receiver, amount, usdcToken.balanceOf(address(this)));
        }
        emit ContractClosed(); 
    }


    // View Functions for Tracking
    function getBuyers() external view returns (Buyer[] memory) {
        return buyers;
    }

    function getBuyerInfo(address buyer) external view returns (Buyer memory) {
        return buyerInfo[buyer];
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getProjectDetails() external view returns (uint256, string memory, uint256, uint256) {
        return (projectId, projectName, CO2BindingAmount, CO2Generated);
    }

    function getContractStatus() external view returns (ContractStatus) {
        return status;
    }
}
