// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Enums} from "../utils/Enums.sol";
import {Events} from "../utils/Events.sol";
import {Errors} from "../utils/Errors.sol";

/**
 * @title ReceiptNFTModule
 * @dev Soulbound NFT module for transaction receipts
 */
contract ReceiptNFTModule is ERC721 {
    address private _owner;
    uint256 private _tokenIdCounter;

    struct ReceiptData {
        Enums.TxType txType;
        uint256 amount;
        uint256 timestamp;
        string cid;
    }

    mapping(uint256 => ReceiptData) public receiptData;

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() internal view {
        if (_owner != msg.sender) {
            revert Errors.Unauthorized();
        }
    }

    constructor(address initialOwner) ERC721("GajiKita Receipt", "GKR") {
        _owner = initialOwner;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Mints a new receipt NFT (internal function)
     */
    function _mintReceipt(address _to, Enums.TxType _txType, uint256 _amount, string memory _cid) internal virtual {
        uint256 tokenId = _tokenIdCounter++;
        
        // Store receipt data
        receiptData[tokenId] = ReceiptData({
            txType: _txType,
            amount: _amount,
            timestamp: block.timestamp,
            cid: _cid
        });
        
        _safeMint(_to, tokenId);
        
        emit Events.ReceiptMinted(tokenId, _to, _txType, _amount, _cid);
    }

    /**
     * @dev Burns a receipt NFT (internal function)
     */
    function _burnReceipt(uint256 _tokenId) internal {
        _burn(_tokenId);
        delete receiptData[_tokenId];
    }

    /**
     * @dev Returns receipt data for a token ID
     */
    function getReceiptData(uint256 _tokenId) external view returns (ReceiptData memory) {
        return receiptData[_tokenId];
    }

    /**
     * @dev Internal function that prevents transfers to make NFT soulbound
     * In OpenZeppelin v5.x, token transfers are handled by _update function
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        // Prevent transfers (but allow minting and burning)
        if (_ownerOf(tokenId) != address(0) && to != address(0)) {
            revert Errors.TransferNotAllowed();
        }
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Overrides approval functions to make NFT soulbound
     */
    function approve(address /* to */, uint256 /* tokenId */) public virtual override(ERC721) {
        revert Errors.TransferNotAllowed();
    }

    function setApprovalForAll(address /* operator */, bool /* approved */) public virtual override(ERC721) {
        revert Errors.TransferNotAllowed();
    }
}
