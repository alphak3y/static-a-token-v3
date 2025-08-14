// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';

interface IStaticATokenStructs {
  struct GlobalState {
    IERC20 aToken;
    address aTokenUnderlying;
    address[] rewardTokens;
  }
}