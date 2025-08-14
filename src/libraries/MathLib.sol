// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {DataTypes} from 'aave-address-book/AaveV3.sol';
import {MathUtils} from 'aave-v3-core/contracts/protocol/libraries/math/MathUtils.sol';
import {WadRayMath} from 'aave-v3-core/contracts/protocol/libraries/math/WadRayMath.sol';
import {ReserveConfiguration} from 'aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {IAToken} from '../interfaces/IAToken.sol';
import {RayMathExplicitRounding} from '../RayMathExplicitRounding.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';

/**
 * @title MathLib
 * @notice Library for mathematical operations
 * @dev This library helps reduce bytecode size of StaticATokenLM
 * @author BGD labs
 */
library MathLib {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
  using WadRayMath for uint256;
  using RayMathExplicitRounding for uint256;
  /**
   * @notice Returns the ongoing normalized income for the reserve
   * @dev A value of 1e27 means there is no income. As time passes, the income is accrued
   * @dev A value of 2*1e27 means for each unit of asset one unit of income has been accrued
   * @param reserve The reserve object
   * @return The normalized income, expressed in ray
   */
  function getNormalizedIncome(
    DataTypes.ReserveData memory reserve
  ) external view returns (uint256) {
    return _getNormalizedIncome(reserve);
  }

  function _getNormalizedIncome(
    DataTypes.ReserveData memory reserve
  ) private view returns (uint256) {
    uint40 timestamp = reserve.lastUpdateTimestamp;

    //solium-disable-next-line
    if (timestamp == block.timestamp) {
      //if the index was updated in the same block, no need to perform any calculation
      return reserve.liquidityIndex;
    } else {
      return
        MathUtils.calculateLinearInterest(reserve.currentLiquidityRate, timestamp).rayMul(
          reserve.liquidityIndex
        );
    }
  }

  /**
   * @notice Calculate the maximum deposit amount based on reserve configuration
   * @param reserveData The reserve data
   * @return The maximum amount that can be deposited
   */
  function calculateMaxDeposit(
    DataTypes.ReserveData memory reserveData
  ) external view returns (uint256) {
    // if inactive, paused or frozen users cannot deposit underlying
    if (
      !reserveData.configuration.getActive() ||
      reserveData.configuration.getPaused() ||
      reserveData.configuration.getFrozen()
    ) {
      return 0;
    }

    uint256 supplyCap = reserveData.configuration.getSupplyCap() *
      (10 ** reserveData.configuration.getDecimals());
    // if no supply cap deposit is unlimited
    if (supplyCap == 0) return type(uint256).max;
    // return remaining supply cap margin
    uint256 currentSupply = (IAToken(reserveData.aTokenAddress).scaledTotalSupply() +
      reserveData.accruedToTreasury).rayMulRoundUp(_getNormalizedIncome(reserveData));
    return currentSupply > supplyCap ? 0 : supplyCap - currentSupply;
  }

  /**
   * @notice Calculate the maximum redeem amount based on reserve configuration
   * @param reserveData The reserve data
   * @param aTokenAddress The aToken address
   * @param userBalance The user's balance
   * @return The maximum amount that can be redeemed
   */
  function calculateMaxRedeem(
    DataTypes.ReserveData memory reserveData,
    address aTokenAddress,
    uint256 userBalance
  ) external view returns (uint256) {
    // if paused or inactive users cannot withdraw underlying
    if (
      !reserveData.configuration.getActive() ||
      reserveData.configuration.getPaused()
    ) {
      return 0;
    }

    // otherwise users can withdraw up to the available amount
    uint256 underlyingTokenBalanceInShares = (IERC20(aTokenAddress).balanceOf(reserveData.aTokenAddress))
      .rayDivRoundDown(_getNormalizedIncome(reserveData));
    return
      underlyingTokenBalanceInShares >= userBalance
        ? userBalance
        : underlyingTokenBalanceInShares;
  }
}
