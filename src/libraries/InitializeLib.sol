// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {IAToken} from '../interfaces/IAToken.sol';
import {IStaticATokenStructs} from '../interfaces/IStaticATokenStructs.sol';
import {RewardManagementLib} from './RewardManagementLib.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {SafeCast} from 'solidity-utils/contracts/oz-common/SafeCast.sol';
import {IStaticATokenLM} from '../interfaces/IStaticATokenLM.sol';

library InitializeLib {
  using SafeERC20 for IERC20;
  using SafeCast for uint256;

  IPool public constant POOL = IPool(0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b);
  IRewardsController public constant INCENTIVES_CONTROLLER = IRewardsController(0x5280b0Bac1c8342F9dCeA2bC5B6121A1473A368C);

  event Initialized(address indexed aToken, string staticATokenName, string staticATokenSymbol);

  function initialize(
    address newAToken,
    string calldata staticATokenName,
    string calldata staticATokenSymbol,
    IStaticATokenStructs.GlobalState storage globalState,
    mapping(address => RewardManagementLib.RewardIndexCache) storage _startIndex
  ) external {
    require(IAToken(newAToken).POOL() == address(POOL), 'Invalid pool');
    globalState.aToken = IERC20(newAToken);
    globalState.aTokenUnderlying = IAToken(newAToken).UNDERLYING_ASSET_ADDRESS();

    IERC20(globalState.aTokenUnderlying).forceApprove(address(POOL), type(uint256).max);

    RewardManagementLib.refreshRewardTokens(globalState, _startIndex);

    emit Initialized(newAToken, staticATokenName, staticATokenSymbol);
  }


}