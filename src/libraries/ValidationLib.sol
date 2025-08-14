// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {StaticATokenErrors} from '../StaticATokenErrors.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';

/**
 * @title ValidationLib
 * @notice Library for validation operations
 * @dev This library helps reduce bytecode size of StaticATokenLM
 * @author BGD labs
 */
library ValidationLib {
  /**
   * @notice Validate deposit parameters
   * @param receiver The receiver address
   * @param shares The shares amount
   * @param assets The assets amount
   * @param maxDeposit The maximum deposit amount
   * @param maxMint The maximum mint amount
   */
  function validateDeposit(
    address receiver,
    uint256 shares,
    uint256 assets,
    uint256 maxDeposit,
    uint256 maxMint
  ) external pure {
    require(receiver != address(0), StaticATokenErrors.INVALID_RECIPIENT);
    require(shares == 0 || assets == 0, StaticATokenErrors.ONLY_ONE_AMOUNT_FORMAT_ALLOWED);
    
    if (shares > 0) {
      require(shares <= maxMint, 'ERC4626: mint more than max');
    } else {
      require(assets <= maxDeposit, 'ERC4626: deposit more than max');
    }
  }

  /**
   * @notice Validate withdrawal parameters
   * @param receiver The receiver address
   * @param shares The shares amount
   * @param assets The assets amount
   * @param maxWithdraw The maximum withdrawal amount
   * @param maxRedeem The maximum redeem amount
   */
  function validateWithdrawal(
    address receiver,
    uint256 shares,
    uint256 assets,
    uint256 maxWithdraw,
    uint256 maxRedeem
  ) external pure {
    require(receiver != address(0), StaticATokenErrors.INVALID_RECIPIENT);
    require(shares == 0 || assets == 0, StaticATokenErrors.ONLY_ONE_AMOUNT_FORMAT_ALLOWED);
    require(shares != assets, StaticATokenErrors.INVALID_ZERO_AMOUNT);
    
    if (shares > 0) {
      require(shares <= maxRedeem, 'ERC4626: redeem more than max');
    } else {
      require(assets <= maxWithdraw, 'ERC4626: withdraw more than max');
    }
  }

  /**
   * @notice Validate meta transaction parameters
   * @param owner The owner address
   * @param deadline The deadline timestamp
   */
  function validateMetaTransaction(
    address owner,
    uint256 deadline
  ) external view {
    require(owner != address(0), StaticATokenErrors.INVALID_OWNER);
    //solium-disable-next-line
    require(deadline >= block.timestamp, StaticATokenErrors.INVALID_EXPIRATION);
  }

  /**
   * @notice Validate claimer permissions
   * @param onBehalfOf The address to claim on behalf of
   * @param claimer The claimer address
   * @param incentivesController The incentives controller
   */
  function validateClaimer(
    address onBehalfOf,
    address claimer,
    address incentivesController
  ) external view {
    require(
      claimer == onBehalfOf || claimer == IRewardsController(incentivesController).getClaimer(onBehalfOf),
      StaticATokenErrors.INVALID_CLAIMER
    );
  }

  /**
   * @notice Validate depositor for meta transactions
   * @param depositor The depositor address
   */
  function validateDepositor(address depositor) external pure {
    require(depositor != address(0), StaticATokenErrors.INVALID_DEPOSITOR);
  }
}
