// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizeStableCoin} from "../src/DecentrailizeStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] private s_tokenAddress;
    address[] private s_priceFeed;

    function run() external returns (DecentralizeStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethPriceFeed, address wbtcPriceFeed, address wbtc, address weth, uint256 deployerKey) =
            helperConfig.ActiveConfig();
        s_tokenAddress = [weth, wbtc];
        s_priceFeed = [wethPriceFeed, wbtcPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizeStableCoin dsc = new DecentralizeStableCoin();
        //address[] memory _tokenAddress, address[] memory _priceFeed, address dscAddress
        DSCEngine dSCEngine = new DSCEngine(s_tokenAddress, s_priceFeed, address(dsc));
        dsc.transferOwnership(address(dSCEngine));
        vm.stopBroadcast();
        return (dsc, dSCEngine, helperConfig);
    }
}
