// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import 'forge-std/Test.sol';
import {Script} from 'forge-std/Script.sol';
import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';
import {StaticATokenFactory} from '../src/StaticATokenFactory.sol';
import {StaticATokenLM} from '../src/StaticATokenLM.sol';
import {IPool} from 'aave-address-book/AaveV3.sol';
import {IRewardsController} from 'aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol';
import {TransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol';

/**
 * @title DeployUpgradeableFactory
 * @notice Script to deploy an upgradeable StaticATokenFactory
 * @dev This script can be used to deploy on any network with configurable parameters
 * @author BGD labs
 */
contract DeployUpgradeableFactory is Script {
  // Configuration parameters - these can be set via environment variables or constructor
  address public proxyFactory;
  address public proxyAdmin;
  address public pool;
  address public rewardsController;
  bool public createStaticATokens;

  /**
   * @notice Deploy an upgradeable StaticATokenFactory
   * @return factory The deployed factory address
   * @return staticImpl The deployed static token implementation address
   * @return factoryImpl The deployed factory implementation address
   */
  function deploy() public returns (
    StaticATokenFactory factory,
    StaticATokenLM staticImpl,
    StaticATokenFactory factoryImpl
  ) {
    // Validate inputs
    require(proxyAdmin != address(0), "INVALID_PROXY_ADMIN");
    require(pool != address(0), "INVALID_POOL");
    require(rewardsController != address(0), "INVALID_REWARDS_CONTROLLER");

    if (proxyFactory == address(0)) {
      proxyFactory = address(new TransparentProxyFactory());
    }

    // Deploy static token implementation
    staticImpl = new StaticATokenLM(IPool(pool), IRewardsController(rewardsController));
    console.log("StaticATokenLM implementation deployed at:", address(staticImpl));

    // Deploy factory implementation
    factoryImpl = new StaticATokenFactory(
      IPool(pool),
      proxyAdmin,
      ITransparentProxyFactory(proxyFactory),
      address(staticImpl)
    );
    console.log("StaticATokenFactory implementation deployed at:", address(factoryImpl));

    // Deploy factory proxy
    bytes memory initData = abi.encodeWithSelector(StaticATokenFactory.initialize.selector);
    address factoryProxy = ITransparentProxyFactory(proxyFactory).create(
      address(factoryImpl),
      proxyAdmin,
      initData
    );
    factory = StaticATokenFactory(factoryProxy);
    console.log("StaticATokenFactory proxy deployed at:", address(factory));

    // Optionally create static aTokens for all reserves
    if (createStaticATokens) {
      address[] memory reserves = IPool(pool).getReservesList();
      factory.createStaticATokens(reserves);
      console.log("Created static aTokens for", reserves.length, "reserves");
    }

    return (factory, staticImpl, factoryImpl);
  }

  /**
   * @notice Run the deployment script
   * @dev This function can be called with forge script
   */
  function run() external {
    vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

    createStaticATokens = true;
    proxyAdmin = 0x582668B6AA564Bdb6380d5c4f80A59C49C65cA83;
    pool = 0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b;
    rewardsController = 0x5280b0Bac1c8342F9dCeA2bC5B6121A1473A368C;

    // Deploy the factory
    (StaticATokenFactory factory, StaticATokenLM staticImpl, StaticATokenFactory factoryImpl) = deploy();

    vm.stopBroadcast();

    // Log deployment information
    console.log("=== Deployment Summary ===");
    console.log("Network:", block.chainid);
    console.log("StaticATokenLM Implementation:", address(staticImpl));
    console.log("StaticATokenFactory Implementation:", address(factoryImpl));
    console.log("StaticATokenFactory Proxy:", address(factory));
    console.log("Proxy Admin:", proxyAdmin);
    console.log("Pool:", pool);
    console.log("Rewards Controller:", rewardsController);
  }
}