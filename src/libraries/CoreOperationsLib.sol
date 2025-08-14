// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {StaticATokenErrors} from '../StaticATokenErrors.sol';
import {ConversionLib} from './ConversionLib.sol';
import {IERC4626} from 'src/interfaces/IERC4626.sol';

/**
 * @title CoreOperationsLib
 * @notice Library for core deposit/withdraw operations
 * @dev This library helps reduce bytecode size of StaticATokenLM
 * @author BGD labs
 */
library CoreOperationsLib {
  using SafeERC20 for IERC20;

  struct DepositParams {
    address depositor;
    address receiver;
    uint256 shares;
    uint256 assets;
    uint16 referralCode;
    bool depositToAave;
    address aTokenUnderlying;
    IERC20 aToken;
    IPool pool;
    uint256 currentRate;
    uint256 maxMintAmount;
    uint256 maxDepositAmount;
  }

  struct WithdrawParams {
    address owner;
    address receiver;
    uint256 shares;
    uint256 assets;
    bool withdrawFromAave;
    address aTokenUnderlying;
    IERC20 aToken;
    IPool pool;
    uint256 currentRate;
    uint256 maxRedeemAmount;
    uint256 maxWithdrawAmount;
    uint256 ownerBalance;
    uint256 allowance;
  }

  /**
   * @notice Execute deposit operation
   * @param params Deposit parameters
   * @return shares The amount of shares minted
   * @return assets The amount of assets deposited
   */
  function executeDeposit(
    DepositParams memory params
  ) external returns (uint256 shares, uint256 assets) {
    assets = params.assets;
    shares = params.shares;
    
    if (shares > 0) {
      if (params.depositToAave) {
        require(shares <= params.maxMintAmount, 'ERC4626: mint more than max');
      }
      assets = ConversionLib.previewMint(shares, params.currentRate);
    } else {
      if (params.depositToAave) {
        require(assets <= params.maxDepositAmount, 'ERC4626: deposit more than max');
      }
      shares = ConversionLib.previewDeposit(assets, params.currentRate);
    }
    require(shares != 0, StaticATokenErrors.INVALID_ZERO_AMOUNT);

    if (params.depositToAave) {
      IERC20(params.aTokenUnderlying).safeTransferFrom(params.depositor, address(this), assets);
      params.pool.deposit(params.aTokenUnderlying, assets, address(this), params.referralCode);
    } else {
      params.aToken.safeTransferFrom(params.depositor, address(this), assets);
    }

    // emit IERC4626.Deposit(params.depositor, params.receiver, assets, shares);

    return (shares, assets);
  }

  /**
   * @notice Execute withdraw operation
   * @param params Withdraw parameters
   * @return shares The amount of shares burned
   * @return assets The amount of assets withdrawn
   */
  function executeWithdraw(
    WithdrawParams memory params
  ) external returns (uint256 shares, uint256 assets) {
    require(params.receiver != address(0), StaticATokenErrors.INVALID_RECIPIENT);
    require(params.shares == 0 || params.assets == 0, StaticATokenErrors.ONLY_ONE_AMOUNT_FORMAT_ALLOWED);
    require(params.shares != params.assets, StaticATokenErrors.INVALID_ZERO_AMOUNT);

    assets = params.assets;
    shares = params.shares;

    if (shares > 0) {
      if (params.withdrawFromAave) {
        require(shares <= params.maxRedeemAmount, 'ERC4626: redeem more than max');
      }
      assets = ConversionLib.previewRedeem(shares, params.currentRate);
    } else {
      if (params.withdrawFromAave) {
        require(assets <= params.maxWithdrawAmount, 'ERC4626: withdraw more than max');
      }
      shares = ConversionLib.previewWithdraw(assets, params.currentRate);
    }

    if (params.withdrawFromAave) {
      params.pool.withdraw(params.aTokenUnderlying, assets, params.receiver);
    } else {
      params.aToken.safeTransfer(params.receiver, assets);
    }

    return (shares, assets);
  }

  /**
   * @notice Handle allowance check and update
   * @param owner The owner address
   * @param spender The spender address
   * @param shares The shares amount
   * @param allowanceMapping The allowance mapping
   * @return newAllowance The updated allowance
   */
  function handleAllowance(
    address owner,
    address spender,
    uint256 shares,
    mapping(address => mapping(address => uint256)) storage allowanceMapping
  ) external returns (uint256 newAllowance) {
    if (spender != owner) {
      uint256 allowed = allowanceMapping[owner][spender];
      if (allowed != type(uint256).max) {
        allowanceMapping[owner][spender] = allowed - shares;
        return allowed - shares;
      }
    }
    return type(uint256).max;
  }
}
