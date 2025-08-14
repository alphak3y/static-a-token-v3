// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {RayMathExplicitRounding, Rounding} from '../RayMathExplicitRounding.sol';

/**
 * @title ConversionLib
 * @notice Library for share/asset conversion operations
 * @dev This library helps reduce bytecode size of StaticATokenLM
 * @author BGD labs
 */
library ConversionLib {
  using RayMathExplicitRounding for uint256;

  function convertToShares(uint256 assets, uint256 rate, Rounding rounding) external pure returns (uint256) {
    return _convertToShares(assets, rate, rounding);
  }

  function convertToAssets(uint256 shares, uint256 rate, Rounding rounding) external pure returns (uint256) {
    return _convertToAssets(shares, rate, rounding);
  }
  /**
   * @notice Convert assets to shares using the given rate
   * @param assets The amount of assets to convert
   * @param rate The current rate (normalized income)
   * @param rounding The rounding direction
   * @return The amount of shares
   */
  function _convertToShares(
    uint256 assets,
    uint256 rate,
    Rounding rounding
  ) private pure returns (uint256) {
    if (rounding == Rounding.UP) return assets.rayDivRoundUp(rate);
    return assets.rayDivRoundDown(rate);
  }

  /**
   * @notice Convert shares to assets using the given rate
   * @param shares The amount of shares to convert
   * @param rate The current rate (normalized income)
   * @param rounding The rounding direction
   * @return The amount of assets
   */
  function _convertToAssets(
    uint256 shares,
    uint256 rate,
    Rounding rounding
  ) private pure returns (uint256) {
    if (rounding == Rounding.UP) return shares.rayMulRoundUp(rate);
    return shares.rayMulRoundDown(rate);
  }

  /**
   * @notice Preview deposit - convert assets to shares with DOWN rounding
   * @param assets The amount of assets to deposit
   * @param rate The current rate (normalized income)
   * @return The amount of shares that would be minted
   */
  function previewDeposit(uint256 assets, uint256 rate) external pure returns (uint256) {
    return _convertToShares(assets, rate, Rounding.DOWN);
  }

  /**
   * @notice Preview mint - convert shares to assets with UP rounding
   * @param shares The amount of shares to mint
   * @param rate The current rate (normalized income)
   * @return The amount of assets that would be deposited
   */
  function previewMint(uint256 shares, uint256 rate) external pure returns (uint256) {
    return _convertToAssets(shares, rate, Rounding.UP);
  }

  /**
   * @notice Preview withdraw - convert assets to shares with UP rounding
   * @param assets The amount of assets to withdraw
   * @param rate The current rate (normalized income)
   * @return The amount of shares that would be burned
   */
  function previewWithdraw(uint256 assets, uint256 rate) external pure returns (uint256) {
    return _convertToShares(assets, rate, Rounding.UP);
  }

  /**
   * @notice Preview redeem - convert shares to assets with DOWN rounding
   * @param shares The amount of shares to redeem
   * @param rate The current rate (normalized income)
   * @return The amount of assets that would be withdrawn
   */
  function previewRedeem(uint256 shares, uint256 rate) external pure returns (uint256) {
    return _convertToAssets(shares, rate, Rounding.DOWN);
  }
}
