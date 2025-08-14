// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPool} from 'aave-v3-core/contracts/interfaces/IPool.sol';
import {DataTypes} from 'aave-address-book/AaveV3.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {SafeCast} from 'solidity-utils/contracts/oz-common/SafeCast.sol';
import {Initializable} from 'solidity-utils/contracts/transparent-proxy/Initializable.sol';
import {IERC20Metadata} from 'solidity-utils/contracts/oz-common/interfaces/IERC20Metadata.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';

import {IStaticATokenLM} from './interfaces/IStaticATokenLM.sol';
import {IAToken} from './interfaces/IAToken.sol';
import {ERC20} from './ERC20.sol';
import {IInitializableStaticATokenLM} from './interfaces/IInitializableStaticATokenLM.sol';
import {StaticATokenErrors} from './StaticATokenErrors.sol';
import {RayMathExplicitRounding, Rounding} from './RayMathExplicitRounding.sol';
import {IERC4626} from './interfaces/IERC4626.sol';
import {IStaticATokenStructs} from './interfaces/IStaticATokenStructs.sol';

// Import libraries
import {RewardManagementLib} from './libraries/RewardManagementLib.sol';
import {ConversionLib} from './libraries/ConversionLib.sol';
import {MathLib} from './libraries/MathLib.sol';
import {ValidationLib} from './libraries/ValidationLib.sol';
import {CoreOperationsLib} from './libraries/CoreOperationsLib.sol';
import {MetaTransactionLib} from './libraries/MetaTransactionLib.sol';
import {TokenTransferLib} from './libraries/TokenTransferLib.sol';
import {InitializeLib} from './libraries/InitializeLib.sol';

/**
 * @title StaticATokenLMFullyOptimized
 * @notice Fully optimized wrapper smart contract that allows to deposit tokens on the Aave protocol and receive
 * a token which balance doesn't increase automatically, but uses an ever-increasing exchange rate.
 * It supports claiming liquidity mining rewards from the Aave system.
 * @dev This version uses external libraries for all functionality to minimize bytecode size
 * @author BGD labs
 */
contract StaticATokenLMOptimized is
  Initializable,
  ERC20('STATIC__aToken_IMPL', 'STATIC__aToken_IMPL', 18),
  IStaticATokenLM,
  IERC4626
{
  using SafeERC20 for IERC20;
  using SafeCast for uint256;

  IStaticATokenStructs.GlobalState public globalState;

  uint256 public constant STATIC__ATOKEN_LM_REVISION = 3;

  mapping(address => RewardManagementLib.RewardIndexCache) internal _startIndex;
  mapping(address => mapping(address => RewardManagementLib.UserRewardsData)) internal _userRewardsData;

  constructor() {
    // intentionally left empty
  }

  ///@inheritdoc IInitializableStaticATokenLM
  function initialize(
    address newAToken,
    string calldata staticATokenName,
    string calldata staticATokenSymbol
  ) external initializer {
    InitializeLib.initialize(newAToken, staticATokenName, staticATokenSymbol, globalState, _startIndex);

    name = staticATokenName;
    symbol = staticATokenSymbol;
    decimals = IERC20Metadata(newAToken).decimals();
  }

  ///@inheritdoc IStaticATokenLM
  function refreshRewardTokens() public override {
    RewardManagementLib.refreshRewardTokens(globalState, _startIndex);
  }

  ///@inheritdoc IStaticATokenLM
  function isRegisteredRewardToken(address reward) public view override returns (bool) {
    return RewardManagementLib.isRegisteredRewardToken(reward, _startIndex);
  }

  ///@inheritdoc IStaticATokenLM
  function deposit(
    uint256 assets,
    address receiver,
    uint16 referralCode,
    bool depositToAave
  ) external returns (uint256) {
    (uint256 shares, ) = _deposit(msg.sender, receiver, 0, assets, referralCode, depositToAave);
    return shares;
  }

  ///@inheritdoc IStaticATokenLM
  function metaDeposit(
    address depositor,
    address receiver,
    uint256 assets,
    uint16 referralCode,
    bool depositToAave,
    uint256 deadline,
    IStaticATokenLM.PermitParams calldata permit,
    IStaticATokenLM.SignatureParams calldata sigParams
  ) external returns (uint256) {
    ValidationLib.validateDepositor(depositor);
    ValidationLib.validateMetaTransaction(depositor, deadline);
    
    uint256 nonce = nonces[depositor];
    nonces[depositor] = nonce + 1;

    bool isValid = MetaTransactionLib.verifyDepositSignature(
      depositor,
      receiver,
      assets,
      referralCode,
      depositToAave,
      deadline,
      MetaTransactionLib.PermitParams({
        owner: permit.owner,
        spender: permit.spender,
        value: permit.value,
        deadline: permit.deadline,
        v: permit.v,
        r: permit.r,
        s: permit.s
      }),
      MetaTransactionLib.SignatureParams({
        v: sigParams.v,
        r: sigParams.r,
        s: sigParams.s
      }),
      nonce,
      name
    );
    require(isValid, StaticATokenErrors.INVALID_SIGNATURE);

    MetaTransactionLib.executePermit(
      MetaTransactionLib.PermitParams({
        owner: permit.owner,
        spender: permit.spender,
        value: permit.value,
        deadline: permit.deadline,
        v: permit.v,
        r: permit.r,
        s: permit.s
      }),
      depositToAave,
      globalState.aTokenUnderlying,
      address(globalState.aToken)
    );
    
    (uint256 shares, ) = _deposit(depositor, receiver, 0, assets, referralCode, depositToAave);
    return shares;
  }

  ///@inheritdoc IStaticATokenLM
  function metaWithdraw(
    address owner,
    address receiver,
    uint256 shares,
    uint256 assets,
    bool withdrawFromAave,
    uint256 deadline,
    IStaticATokenLM.SignatureParams calldata sigParams
  ) external returns (uint256, uint256) {
    ValidationLib.validateMetaTransaction(owner, deadline);
    uint256 nonce = nonces[owner];
    nonces[owner] = nonce + 1;

    bool isValid = MetaTransactionLib.verifyWithdrawalSignature(
      owner,
      receiver,
      shares,
      assets,
      withdrawFromAave,
      deadline,
      MetaTransactionLib.SignatureParams({
        v: sigParams.v,
        r: sigParams.r,
        s: sigParams.s
      }),
      nonce,
      name
    );
    require(isValid, StaticATokenErrors.INVALID_SIGNATURE);

    return _withdraw(owner, receiver, shares, assets, withdrawFromAave);
  }

  ///@inheritdoc IERC4626
  function previewRedeem(uint256 shares) public view virtual returns (uint256) {
    return ConversionLib.previewRedeem(shares, rate());
  }

  ///@inheritdoc IERC4626
  function previewMint(uint256 shares) public view virtual returns (uint256) {
    return ConversionLib.previewMint(shares, rate());
  }

  ///@inheritdoc IERC4626
  function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
    return ConversionLib.previewWithdraw(assets, rate());
  }

  ///@inheritdoc IERC4626
  function previewDeposit(uint256 assets) public view virtual returns (uint256) {
    return ConversionLib.previewDeposit(assets, rate());
  }

  ///@inheritdoc IStaticATokenLM
  function rate() public view returns (uint256) {
    return RewardManagementLib.POOL.getReserveNormalizedIncome(globalState.aTokenUnderlying);
  }

  ///@inheritdoc IStaticATokenLM
  function collectAndUpdateRewards(address reward) public returns (uint256) {
    return TokenTransferLib.collectAndUpdateRewards(reward, address(globalState.aToken), RewardManagementLib.INCENTIVES_CONTROLLER);
  }

  ///@inheritdoc IStaticATokenLM
  function claimRewardsOnBehalf(
    address onBehalfOf,
    address receiver,
    address[] memory rewards
  ) external {
    ValidationLib.validateClaimer(onBehalfOf, msg.sender, address(RewardManagementLib.INCENTIVES_CONTROLLER));
    RewardManagementLib.claimRewardsOnBehalf(onBehalfOf, receiver, rewards, globalState, _startIndex, _userRewardsData, balanceOf, decimals);
  }

  ///@inheritdoc IStaticATokenLM
  function claimRewards(address receiver, address[] memory rewards) external {
    RewardManagementLib.claimRewardsOnBehalf(msg.sender, receiver, rewards, globalState, _startIndex, _userRewardsData, balanceOf, decimals);
  }

  ///@inheritdoc IStaticATokenLM
  function claimRewardsToSelf(address[] memory rewards) external {
    RewardManagementLib.claimRewardsOnBehalf(msg.sender, msg.sender, rewards, globalState, _startIndex, _userRewardsData, balanceOf, decimals);
  }

  ///@inheritdoc IStaticATokenLM
  function getCurrentRewardsIndex(address reward) public view returns (uint256) {
    return TokenTransferLib.getCurrentRewardsIndex(reward, address(globalState.aToken), RewardManagementLib.INCENTIVES_CONTROLLER);
  }

  ///@inheritdoc IStaticATokenLM
  function getTotalClaimableRewards(address reward) external view returns (uint256) {
    return TokenTransferLib.getTotalClaimableRewards(reward, address(globalState.aToken), RewardManagementLib.INCENTIVES_CONTROLLER);
  }

  ///@inheritdoc IStaticATokenLM
  function getClaimableRewards(address user, address reward) external view returns (uint256) {
    return _getClaimableRewards(user, reward, balanceOf[user], getCurrentRewardsIndex(reward));
  }

  ///@inheritdoc IStaticATokenLM
  function getUnclaimedRewards(address user, address reward) external view returns (uint256) {
    return _userRewardsData[user][reward].unclaimedRewards;
  }

  ///@inheritdoc IERC4626
  function asset() external view returns (address) {
    return address(globalState.aTokenUnderlying);
  }

  ///@inheritdoc IStaticATokenLM
  function aToken() external view returns (IERC20) {
    return globalState.aToken;
  }

  ///@inheritdoc IStaticATokenLM
  function rewardTokens() external view returns (address[] memory) {
    return globalState.rewardTokens;
  }

  ///@inheritdoc IERC4626
  function totalAssets() external view returns (uint256) {
    return globalState.aToken.balanceOf(address(this));
  }

  ///@inheritdoc IERC4626
  function convertToShares(uint256 assets) external view returns (uint256) {
    return ConversionLib.convertToShares(assets, rate(), Rounding.DOWN);
  }

  ///@inheritdoc IERC4626
  function convertToAssets(uint256 shares) external view returns (uint256) {
    return ConversionLib.convertToAssets(shares, rate(), Rounding.DOWN);
  }

  ///@inheritdoc IERC4626
  function maxMint(address) public view virtual returns (uint256) {
    uint256 assets = maxDeposit(address(0));
    if (assets == type(uint256).max) return type(uint256).max;
    return ConversionLib.convertToShares(assets, rate(), Rounding.DOWN);
  }

  ///@inheritdoc IERC4626
  function maxWithdraw(address owner) public view virtual returns (uint256) {
    uint256 shares = maxRedeem(owner);
    return ConversionLib.convertToAssets(shares, rate(), Rounding.DOWN);
  }

  ///@inheritdoc IERC4626
  function maxRedeem(address owner) public view virtual returns (uint256) {
    address cachedATokenUnderlying = globalState.aTokenUnderlying;
    DataTypes.ReserveData memory reserveData = RewardManagementLib.POOL.getReserveData(cachedATokenUnderlying);
    return MathLib.calculateMaxRedeem(reserveData, cachedATokenUnderlying, balanceOf[owner]);
  }

  ///@inheritdoc IERC4626
  function maxDeposit(address) public view virtual returns (uint256) {
    DataTypes.ReserveData memory reserveData = RewardManagementLib.POOL.getReserveData(globalState.aTokenUnderlying);
    return MathLib.calculateMaxDeposit(reserveData);
  }

  ///@inheritdoc IERC4626
  function deposit(uint256 assets, address receiver) external virtual returns (uint256) {
    (uint256 shares, ) = _deposit(msg.sender, receiver, 0, assets, 0, true);
    return shares;
  }

  ///@inheritdoc IERC4626
  function mint(uint256 shares, address receiver) external virtual returns (uint256) {
    (, uint256 assets) = _deposit(msg.sender, receiver, shares, 0, 0, true);
    return assets;
  }

  ///@inheritdoc IERC4626
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  ) external virtual returns (uint256) {
    (uint256 shares, ) = _withdraw(owner, receiver, 0, assets, true);
    return shares;
  }

  ///@inheritdoc IERC4626
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) external virtual returns (uint256) {
    (, uint256 assets) = _withdraw(owner, receiver, shares, 0, true);
    return assets;
  }

  ///@inheritdoc IStaticATokenLM
  function redeem(
    uint256 shares,
    address receiver,
    address owner,
    bool withdrawFromAave
  ) external virtual returns (uint256, uint256) {
    return _withdraw(owner, receiver, shares, 0, withdrawFromAave);
  }

  function _deposit(
    address depositor,
    address receiver,
    uint256 _shares,
    uint256 _assets,
    uint16 referralCode,
    bool depositToAave
  ) internal returns (uint256, uint256) {
    CoreOperationsLib.DepositParams memory params = CoreOperationsLib.DepositParams({
      depositor: depositor,
      receiver: receiver,
      shares: _shares,
      assets: _assets,
      referralCode: referralCode,
      depositToAave: depositToAave,
      aTokenUnderlying: globalState.aTokenUnderlying,
      aToken: globalState.aToken,
      pool: RewardManagementLib.POOL,
      currentRate: rate(),
      maxMintAmount: maxMint(receiver),
      maxDepositAmount: maxDeposit(receiver)
    });

    (uint256 shares, uint256 assets) = CoreOperationsLib.executeDeposit(params);
    
    _mint(receiver, shares);

    return (shares, assets);
  }

  function _withdraw(
    address owner,
    address receiver,
    uint256 _shares,
    uint256 _assets,
    bool withdrawFromAave
  ) internal returns (uint256, uint256) {
    CoreOperationsLib.WithdrawParams memory params = CoreOperationsLib.WithdrawParams({
      owner: owner,
      receiver: receiver,
      shares: _shares,
      assets: _assets,
      withdrawFromAave: withdrawFromAave,
      aTokenUnderlying: globalState.aTokenUnderlying,
      aToken: globalState.aToken,
      pool: RewardManagementLib.POOL,
      currentRate: rate(),
      maxRedeemAmount: maxRedeem(owner),
      maxWithdrawAmount: maxWithdraw(owner),
      ownerBalance: balanceOf[owner],
      allowance: allowance[owner][msg.sender]
    });

    (uint256 shares, uint256 assets) = CoreOperationsLib.executeWithdraw(params);

    if (msg.sender != owner) {
      CoreOperationsLib.handleAllowance(owner, msg.sender, shares, allowance);
    }

    _burn(owner, shares);
    emit Withdraw(msg.sender, receiver, owner, assets, shares);

    return (shares, assets);
  }

  function _beforeTokenTransfer(address from, address to, uint256) internal override {
    for (uint256 i = 0; i < globalState.rewardTokens.length; i++) {
      address rewardToken = address(globalState.rewardTokens[i]);
      uint256 rewardsIndex = getCurrentRewardsIndex(rewardToken);
      if (from != address(0)) {
        _updateUser(from, rewardsIndex, rewardToken);
      }
      if (to != address(0) && from != to) {
        _updateUser(to, rewardsIndex, rewardToken);
      }
    }
  }

  function _updateUser(address user, uint256 currentRewardsIndex, address rewardToken) internal {
    uint256 balance = balanceOf[user];
    if (balance > 0) {
      _userRewardsData[user][rewardToken].unclaimedRewards = _getClaimableRewards(
        user,
        rewardToken,
        balance,
        currentRewardsIndex
      ).toUint128();
    }
    RewardManagementLib.updateRewardsIndex(user, rewardToken, currentRewardsIndex, _userRewardsData);
  }

  function _getClaimableRewards(
    address user,
    address reward,
    uint256 balance,
    uint256 currentRewardsIndex
  ) internal view returns (uint256) {
    return RewardManagementLib.getClaimableRewards(
      user,
      reward,
      balance,
      currentRewardsIndex,
      _startIndex[reward],
      _userRewardsData[user][reward],
      decimals
    );
  }
}
