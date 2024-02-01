// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from
    "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/*
@tittle OracleLib
@author BLockChain Oracle
@notice This libary is used to cheeck the chainLink Oracle for state date
@If a price is stale, the function will revert, and render the DscEngine unstable
we wnat dscEngine to freeze if price feed becomes stale
* so if chainLink network explodes and you have lot of money locked in the protocol...
*/

library OracleLib {
    error OracleLib__stalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function stalePriceCheeckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__stalePrice();
        } else {
            return (roundId, answer, startedAt, updatedAt, answeredInRound);
        }
    }
}
