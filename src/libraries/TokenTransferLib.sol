// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {SafeCast} from 'solidity-utils/contracts/oz-common/SafeCast.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {RewardManagementLib} from './RewardManagementLib.sol';

/**
 * @title TokenTransferLib
 * @notice Library for token transfer and reward operations
 * @dev This library helps reduce bytecode size of StaticATokenLM
 * @author BGD labs
 */
library TokenTransferLib {
  using SafeERC20 for IERC20;
  using SafeCast for uint256;

  /**
   * @notice Claim rewards on behalf of a user
   * @param onBehalfOf The address to claim on behalf of
   * @param receiver The address to receive the rewards
   * @param rewards The addresses of the rewards
   * @param balance The user's balance
   * @param userRewardsDataMapping Mapping of user rewards data
   * @param decimals The token decimals
   * @return totalClaimed Total amount claimed across all rewards
   */
  function claimRewardsOnBehalf(
    address onBehalfOf,
    address receiver,
    address[] memory rewards,
    uint256 balance,
    mapping(address => mapping(address => RewardManagementLib.UserRewardsData)) storage userRewardsDataMapping,
    uint8 decimals
  ) external pure returns (uint256 totalClaimed) {
    // This function is simplified - the actual implementation will be in the main contract
    // to avoid complex function parameters in external library functions
    return 0;
  }

  /**
   * @notice Collect and update rewards
   * @param reward The reward address
   * @param aToken The aToken address
   * @param incentivesController The incentives controller
   * @return amountCollected The amount collected
   */
  function collectAndUpdateRewards(
    address reward,
    address aToken,
    IRewardsController incentivesController
  ) external returns (uint256 amountCollected) {
    if (reward == address(0)) {
      return 0;
    }

    address[] memory assets = new address[](1);
    assets[0] = aToken;

    return incentivesController.claimRewards(assets, type(uint256).max, address(this), reward);
  }

  /**
   * @notice Get current rewards index
   * @param reward The reward address
   * @param aToken The aToken address
   * @param incentivesController The incentives controller
   * @return currentIndex The current rewards index
   */
  function getCurrentRewardsIndex(
    address reward,
    address aToken,
    IRewardsController incentivesController
  ) external view returns (uint256 currentIndex) {
    if (address(reward) == address(0)) {
      return 0;
    }
    (, uint256 nextIndex) = incentivesController.getAssetIndex(aToken, reward);
    return nextIndex;
  }

  /**
   * @notice Get total claimable rewards
   * @param reward The reward address
   * @param aToken The aToken address
   * @param incentivesController The incentives controller
   * @return totalRewards The total claimable rewards
   */
  function getTotalClaimableRewards(
    address reward,
    address aToken,
    IRewardsController incentivesController
  ) external view returns (uint256 totalRewards) {
    if (reward == address(0)) {
      return 0;
    }

    address[] memory assets = new address[](1);
    assets[0] = aToken;
    uint256 freshRewards = incentivesController.getUserRewards(assets, address(this), reward);
    return IERC20(reward).balanceOf(address(this)) + freshRewards;
  }

  /**
   * @notice Update user rewards data
   * @param user The user address
   * @param currentRewardsIndex The current rewards index
   * @param rewardToken The reward token address
   * @param balance The user's balance
   * @param startIndex The reward index cache
   * @param userRewardsData The user's reward data
   * @param decimals The token decimals
   * @return updatedUserRewardsData The updated user rewards data
   */
  function updateUserRewards(
    address user,
    uint256 currentRewardsIndex,
    address rewardToken,
    uint256 balance,
    RewardManagementLib.RewardIndexCache memory startIndex,
    RewardManagementLib.UserRewardsData memory userRewardsData,
    uint8 decimals
  ) external pure returns (RewardManagementLib.UserRewardsData memory updatedUserRewardsData) {
    return RewardManagementLib.updateUser(
      user,
      currentRewardsIndex,
      rewardToken,
      balance,
      startIndex,
      userRewardsData,
      decimals
    );
  }
}
