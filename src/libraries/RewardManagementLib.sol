// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {SafeCast} from 'solidity-utils/contracts/oz-common/SafeCast.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {StaticATokenErrors} from '../StaticATokenErrors.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IStaticATokenStructs} from '../interfaces/IStaticATokenStructs.sol';
import {IStaticATokenLM} from '../interfaces/IStaticATokenLM.sol';
import {TokenTransferLib} from './TokenTransferLib.sol';

/**
 * @title RewardManagementLib
 * @notice Library for managing reward calculations and operations
 * @dev This library helps reduce bytecode size of StaticATokenLM
 * @author BGD labs
 */
library RewardManagementLib {
  using SafeERC20 for IERC20;
  using SafeCast for uint256;

  IPool public constant POOL = IPool(0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b);
  IRewardsController public constant INCENTIVES_CONTROLLER = IRewardsController(0x5280b0Bac1c8342F9dCeA2bC5B6121A1473A368C);

  struct UserRewardsData {
    uint128 rewardsIndexOnLastInteraction; // (in RAYs)
    uint128 unclaimedRewards; // (in RAYs)
  }

  struct RewardIndexCache {
    bool isRegistered;
    uint248 lastUpdatedIndex;
  }

  /**
   * @notice Compute the pending rewards in WAD
   * @param balance The balance of the user
   * @param rewardsIndexOnLastInteraction The index which was on the last interaction of the user
   * @param currentRewardsIndex The current rewards index in the system
   * @param assetUnit One unit of asset (10**decimals)
   * @return The amount of pending rewards in WAD
   */
  function _getPendingRewards(
    uint256 balance,
    uint256 rewardsIndexOnLastInteraction,
    uint256 currentRewardsIndex,
    uint256 assetUnit
  ) private pure returns (uint256) {
    if (balance == 0) {
      return 0;
    }
    return (balance * (currentRewardsIndex - rewardsIndexOnLastInteraction)) / assetUnit;
  }

  /**
   * @notice Compute the claimable rewards for a user
   * @param user The address of the user
   * @param reward The address of the reward
   * @param balance The balance of the user in WAD
   * @param currentRewardsIndex The current rewards index
   * @param startIndex The reward index cache
   * @param userRewardsData The user's reward data
   * @param decimals The token decimals
   * @return The total rewards that can be claimed by the user
   */
  function getClaimableRewards(
    address user,
    address reward,
    uint256 balance,
    uint256 currentRewardsIndex,
    RewardIndexCache memory startIndex,
    UserRewardsData memory userRewardsData,
    uint8 decimals
  ) external pure returns (uint256) {
    return _getClaimableRewards(user, reward, balance, currentRewardsIndex, startIndex, userRewardsData, decimals);
  }

  function _getClaimableRewards(
    address user,
    address reward,
    uint256 balance,
    uint256 currentRewardsIndex,
    RewardIndexCache memory startIndex,
    UserRewardsData memory userRewardsData,
    uint8 decimals
  ) private pure returns (uint256) {
    require(startIndex.isRegistered == true, StaticATokenErrors.REWARD_NOT_INITIALIZED);
    uint256 assetUnit = 10 ** decimals;
    return
      userRewardsData.unclaimedRewards +
      _getPendingRewards(
        balance,
        userRewardsData.rewardsIndexOnLastInteraction == 0
          ? startIndex.lastUpdatedIndex
          : userRewardsData.rewardsIndexOnLastInteraction,
        currentRewardsIndex,
        assetUnit
      );
  }

  /**
   * @notice Update user rewards data
   * @param user The address of the user to update
   * @param currentRewardsIndex The current rewardIndex
   * @param rewardToken The address of the reward token
   * @param balance The user's balance
   * @param startIndex The reward index cache
   * @param userRewardsData The user's reward data
   * @param decimals The token decimals
   * @return updatedUserRewardsData The updated user rewards data
   */
  function updateUser(
    address user,
    uint256 currentRewardsIndex,
    address rewardToken,
    uint256 balance,
    RewardIndexCache memory startIndex,
    UserRewardsData memory userRewardsData,
    uint8 decimals
  ) external pure returns (UserRewardsData memory updatedUserRewardsData) {
    if (balance > 0) {
      updatedUserRewardsData.unclaimedRewards = _getClaimableRewards(
        user,
        rewardToken,
        balance,
        currentRewardsIndex,
        startIndex,
        userRewardsData,
        decimals
      ).toUint128();
    }
    updatedUserRewardsData.rewardsIndexOnLastInteraction = currentRewardsIndex.toUint128();
  }

  function isRegisteredRewardToken(address reward, mapping(address => RewardIndexCache) storage _startIndex) external view returns (bool) {
    return _isRegisteredRewardToken(reward, _startIndex);
  }

  function _isRegisteredRewardToken(address reward, mapping(address => RewardIndexCache) storage _startIndex) private view returns (bool) {
    return _startIndex[reward].isRegistered;
  }

  function _getCurrentRewardsIndex(address reward, mapping(address => RewardIndexCache) storage _startIndex) private view returns (uint256) {
    return _startIndex[reward].lastUpdatedIndex;
  }

  function refreshRewardTokens(IStaticATokenStructs.GlobalState storage globalState, mapping(address => RewardManagementLib.RewardIndexCache) storage _startIndex) external {
    address[] memory rewards = INCENTIVES_CONTROLLER.getRewardsByAsset(address(globalState.aToken));
    for (uint256 i = 0; i < rewards.length; i++) {
      _registerRewardToken(rewards[i], globalState, _startIndex);
    }
  }

  function _registerRewardToken(address reward, IStaticATokenStructs.GlobalState storage globalState, mapping(address => RewardManagementLib.RewardIndexCache) storage _startIndex) private {
    if (_isRegisteredRewardToken(reward, _startIndex)) return;
    uint256 startIndex = _getCurrentRewardsIndex(reward, _startIndex);

    globalState.rewardTokens.push(reward);
    _startIndex[reward] = RewardManagementLib.RewardIndexCache(true, startIndex.toUint240());

    // emit IStaticATokenLM.RewardTokenRegistered(reward, startIndex);
  }

  struct ClaimRewardsOnBehalfLocals {
    uint256 currentRewardsIndex;
    uint256 balance;
    uint256 userReward;
    uint256 totalRewardTokenBalance;
    uint256 unclaimedReward;
    UserRewardsData userRewardsData;
    RewardIndexCache startIndex;
    address reward;
  }

  function claimRewardsOnBehalf(
    address onBehalfOf,
    address receiver,
    address[] memory rewards,
    IStaticATokenStructs.GlobalState storage globalState,
    mapping(address => RewardManagementLib.RewardIndexCache) storage _startIndex,
    mapping(address => mapping(address => RewardManagementLib.UserRewardsData)) storage _userRewardsData,
    mapping(address => uint256) storage _balanceOf,
    uint8 decimals
  ) external {
    ClaimRewardsOnBehalfLocals memory locals;
    for (uint256 i = 0; i < rewards.length; i++) {
      locals.reward = rewards[i];
      if (locals.reward == address(0)) {
        continue;
      }
      locals.currentRewardsIndex = _getCurrentRewardsIndex(locals.reward, _startIndex);
      locals.balance = _balanceOf[onBehalfOf];
      locals.userRewardsData = _userRewardsData[onBehalfOf][locals.reward];
      locals.startIndex = _startIndex[locals.reward];
      locals.userReward = _getClaimableRewards(
        onBehalfOf,
        locals.reward,
        locals.balance,
        locals.currentRewardsIndex,
        locals.startIndex,
        locals.userRewardsData,
        decimals
      );
      locals.totalRewardTokenBalance = IERC20(locals.reward).balanceOf(address(this));
      locals.unclaimedReward = 0;

      if (locals.userReward > locals.totalRewardTokenBalance) {
        locals.totalRewardTokenBalance += TokenTransferLib.collectAndUpdateRewards(address(locals.reward), address(globalState.aToken), INCENTIVES_CONTROLLER);
      }

      if (locals.userReward > locals.totalRewardTokenBalance) {
        locals.unclaimedReward = locals.userReward - locals.totalRewardTokenBalance;
        locals.userReward = locals.totalRewardTokenBalance;
      }
      if (locals.userReward > 0) {
        _userRewardsData[onBehalfOf][locals.reward].unclaimedRewards = locals.unclaimedReward.toUint128();
        _userRewardsData[onBehalfOf][locals.reward].rewardsIndexOnLastInteraction = locals.currentRewardsIndex.toUint128();
        IERC20(locals.reward).safeTransfer(receiver, locals.userReward);
      }
    }
  }
  

  function updateRewardsIndex(
    address user,
    address reward,
    uint256 currentRewardsIndex,
    mapping(address => mapping(address => RewardManagementLib.UserRewardsData)) storage _userRewardsData
  ) external {
    _userRewardsData[user][reward].rewardsIndexOnLastInteraction = currentRewardsIndex.toUint128();
  }
}
