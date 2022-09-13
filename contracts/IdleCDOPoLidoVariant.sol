// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./interfaces/IPoLidoNFT.sol";
import "./interfaces/IStMatic.sol";

import "./IdleCDO.sol";

/// @title IdleCDO variant for Euler Levereged strategy.
/// @author Idle DAO, @massun-onibakuchi
contract IdleCDOPoLidoVariant is IdleCDO, IERC721ReceiverUpgradeable {
    using SafeERC20Upgradeable for IERC20Detailed;

    /// @notice stMatic contract
    IStMATIC public constant stMatic = IStMATIC(0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599);

    /// @notice It allows users to burn their tranche token and redeem their principal + interest back
    /// @dev automatically reverts on lending provider default (_strategyPrice decreased).
    /// @param _amount in tranche tokens
    /// @param _tranche tranche address
    /// @return toRedeem number of underlyings redeemed
    function _withdraw(uint256 _amount, address _tranche) internal override nonReentrant returns (uint256 toRedeem) {
        // check if a deposit is made in the same block from the same user
        _checkSameTx();
        // check if _strategyPrice decreased
        _checkDefault();
        // accrue interest to tranches and updates tranche prices
        _updateAccounting();
        // redeem all user balance if 0 is passed as _amount
        if (_amount == 0) {
            _amount = IERC20Detailed(_tranche).balanceOf(msg.sender);
        }
        require(_amount > 0, "0");
        address _token = token;

        // Calculate the amount to redeem
        toRedeem = (_amount * _tranchePrice(_tranche)) / ONE_TRANCHE_TOKEN;

        // NOTE: modified from IdleCDO
        // request unstaking matic from poLido strategy and receive an nft.
        toRedeem = _liquidate(toRedeem, revertIfTooLow);
        // burn tranche token
        IdleCDOTranche(_tranche).burn(msg.sender, _amount);

        // NOTE: modified from IdleCDO
        // send an PoLido nft not matic to msg.sender
        uint256[] memory tokenIds = stMatic.getOwnedTokens(address(this));
        require(tokenIds.length != 0, "no NFTs");

        uint256 tokenId = tokenIds[tokenIds.length - 1];
        stMatic.poLidoNFT().safeTransferFrom(address(this), msg.sender, tokenId);

        // update NAV with the _amount of underlyings removed
        if (_tranche == AATranche) {
            lastNAVAA -= toRedeem;
        } else {
            lastNAVBB -= toRedeem;
        }

        // update trancheAPRSplitRatio
        _updateSplitRatio();
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
}
