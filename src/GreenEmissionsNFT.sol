// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GreenEmissionsNFT is ERC721, Ownable {

    uint256 public tokenCounter;
    string public baseTokenURI;

    struct ProjectData {
        uint256 projectId;
        string  projectName;
        uint256 CO2BindingAmount;
        address sourceContract;
    }

    mapping(uint256 => ProjectData) public tokenProjectData;

    constructor() ERC721("GreenCertificate", "GCOTB") Ownable(msg.sender) {
        tokenCounter = 0;
    }

    event NFTCreated(address to, uint256 tokenId, uint256 projectId);

    
    function setBaseTokenURI(string memory _newBaseTokenURI) public onlyOwner {
        baseTokenURI = _newBaseTokenURI;
    }


    function createNFT(
        address to,
        uint256 _projectId,
        string memory _projectName,
        uint256 _CO2BindingAmount,
        address _sourceContract
    ) public onlyOwner returns (uint256) {
        tokenCounter++;
        uint256 newItemId = tokenCounter;

        // Store project data associated with this token
        tokenProjectData[newItemId] = ProjectData({
            projectId: _projectId,
            projectName: _projectName,
            CO2BindingAmount: _CO2BindingAmount,
            sourceContract: _sourceContract
        });

        _safeMint(to, newItemId);

        emit NFTCreated(to, newItemId, _projectId);
        
        return newItemId;
    }

    function _tokenExists(uint256 tokenId) public view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }


    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_tokenExists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        return string(abi.encodePacked(baseTokenURI, uint2str(tokenId), ".json"));
    }

    function getProjectData(uint256 tokenId) public view returns (ProjectData memory) {
        require(_tokenExists(tokenId), "ERC721Metadata: Query for nonexistent token");
        return tokenProjectData[tokenId];
    }

    function uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    
}