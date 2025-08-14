// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {StaticATokenErrors} from '../StaticATokenErrors.sol';

/**
 * @title MetaTransactionLib
 * @notice Library for meta transaction operations
 * @dev This library helps reduce bytecode size of StaticATokenLM
 * @author BGD labs
 */
library MetaTransactionLib {
  struct SignatureParams {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  struct PermitParams {
    address owner;
    address spender;
    uint256 value;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  bytes32 public constant METADEPOSIT_TYPEHASH =
    keccak256(
      'Deposit(address depositor,address receiver,uint256 assets,uint16 referralCode,bool depositToAave,uint256 nonce,uint256 deadline,PermitParams permit)'
  );
  bytes32 public constant METAWITHDRAWAL_TYPEHASH =
    keccak256(
      'Withdraw(address owner,address receiver,uint256 shares,uint256 assets,bool withdrawFromAave,uint256 nonce,uint256 deadline)'
  );

  /**
   * @notice Verify deposit signature
   * @param depositor The depositor address
   * @param receiver The receiver address
   * @param assets The assets amount
   * @param referralCode The referral code
   * @param depositToAave Whether to deposit to Aave
   * @param deadline The deadline
   * @param permit The permit parameters
   * @param sigParams The signature parameters
   * @param nonce The current nonce
   * @param name The name of the token
   * @return isValid Whether the signature is valid
   */
  function verifyDepositSignature(
    address depositor,
    address receiver,
    uint256 assets,
    uint16 referralCode,
    bool depositToAave,
    uint256 deadline,
    PermitParams memory permit,
    SignatureParams memory sigParams,
    uint256 nonce,
    string memory name
  ) external view returns (bool isValid) {
    bytes32 digest = keccak256(
      abi.encodePacked(
        '\x19\x01',
        DOMAIN_SEPARATOR(name),
        keccak256(
          abi.encode(
            METADEPOSIT_TYPEHASH,
            depositor,
            receiver,
            assets,
            referralCode,
            depositToAave,
            nonce,
            deadline,
            permit
          )
        )
      )
    );
    
    address recovered = ecrecover(digest, sigParams.v, sigParams.r, sigParams.s);
    return recovered == depositor;
  }

  /**
   * @notice Verify withdrawal signature
   * @param owner The owner address
   * @param receiver The receiver address
   * @param shares The shares amount
   * @param assets The assets amount
   * @param withdrawFromAave Whether to withdraw from Aave
   * @param deadline The deadline
   * @param sigParams The signature parameters
   * @param nonce The current nonce
   * @param name The name of the token
   * @return isValid Whether the signature is valid
   */
  function verifyWithdrawalSignature(
    address owner,
    address receiver,
    uint256 shares,
    uint256 assets,
    bool withdrawFromAave,
    uint256 deadline,
    SignatureParams memory sigParams,
    uint256 nonce,
    string memory name
  ) external view returns (bool isValid) {
    bytes32 digest = keccak256(
      abi.encodePacked(
        '\x19\x01',
        DOMAIN_SEPARATOR(name),
        keccak256(
          abi.encode(
            METAWITHDRAWAL_TYPEHASH,
            owner,
            receiver,
            shares,
            assets,
            withdrawFromAave,
            nonce,
            deadline
          )
        )
      )
    );
    
    address recovered = ecrecover(digest, sigParams.v, sigParams.r, sigParams.s);
    return recovered == owner;
  }

  /**
   * @notice Execute permit if provided
   * @param permit The permit parameters
   * @param depositToAave Whether to deposit to Aave
   * @param aTokenUnderlying The aToken underlying address
   * @param aToken The aToken address
   */
  function executePermit(
    PermitParams memory permit,
    bool depositToAave,
    address aTokenUnderlying,
    address aToken
  ) external {
    if (permit.deadline != 0) {
      try
        IERC20WithPermit(depositToAave ? aTokenUnderlying : aToken).permit(
          permit.owner,
          address(this),
          permit.value,
          permit.deadline,
          permit.v,
          permit.r,
          permit.s
        )
      {} catch {}
    }
  }

  function DOMAIN_SEPARATOR(string memory name) public view returns (bytes32) {
    return computeDomainSeparator(name);
  }

  function computeDomainSeparator(string memory name) internal view returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256(
            'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
          ),
          keccak256(bytes(name)),
          keccak256('1'),
          block.chainid,
          address(this)
        )
      );
  }
}
