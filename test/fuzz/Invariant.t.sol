// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizeStableCoin} from "../../src/DecentrailizeStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "../../src/mock/MockV3Aggregator.sol";
import {Handler} from "./Handler.t.sol";

contract InvatiantTest is StdInvariant, Test {
    DSCEngine dscEngine;
    DecentralizeStableCoin dsc;
    DeployDSC deployDSC;
    HelperConfig helperConfig;

    address wethPriceFeed;
    address wbtcPriceFeed;
    address wbtc;
    address weth;
    uint256 deployerKey;
    address USER = makeAddr("USER");
    address USERerc20;
    Handler handler;

    function setUp() external {
        deployDSC = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployDSC.run();
        (wethPriceFeed, wbtcPriceFeed, wbtc, weth, deployerKey) = helperConfig.ActiveConfig();
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThatTotalSupplyDollars() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposted = ERC20Mock(weth).balanceOf(address(dscEngine));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, wethDeposted);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, wbtcDeposited);
        console.log("totalsupply: %s", totalSupply);
        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);
        console.log("timemint is called", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_getterShouldNotRevert() public view {}
}
