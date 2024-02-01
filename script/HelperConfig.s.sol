// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Script} from "../lib/forge-std/src/Script.sol";
import {MockV3Aggregator} from "../src/mock/MockV3Aggregator.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    Config public ActiveConfig;
    uint8 private constant DECIMALS = 8;
    int256 private constant INITIAL_PRICE = 2000e8;
    uint256 private constant ANVIL = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct Config {
        address wethPriceFeed;
        address wbtcPriceFeed;
        address wbtc;
        address weth;
        uint256 deployerKey;
    }

    constructor() {
        if (block.chainid == 11155111) {
            ActiveConfig = getSepoliaEthConfig();
        } else {
            ActiveConfig = getOrCreateActiveConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (Config memory) {
        return Config({
            wethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateActiveConfig() public returns (Config memory) {
        if (ActiveConfig.wethPriceFeed != address(0)) {
            return ActiveConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator mockV3Aggregator = new MockV3Aggregator(DECIMALS, (INITIAL_PRICE));
        ERC20Mock weth = new ERC20Mock("Wrapped ETH", "WETH", msg.sender, 10000e20);
        ERC20Mock wbtc = new ERC20Mock("Wrapped BTC", "WBTC", msg.sender, 10000e20);

        vm.stopBroadcast();
        return Config({
            wethPriceFeed: address(mockV3Aggregator),
            wbtcPriceFeed: address(mockV3Aggregator),
            wbtc: address(wbtc),
            weth: address(weth),
            deployerKey: ANVIL
        });
    }
}
