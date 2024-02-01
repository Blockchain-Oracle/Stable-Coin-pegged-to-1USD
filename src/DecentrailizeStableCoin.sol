// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {ERC20, ERC20Burnable} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title Dententralize stable coin
/// @author BlockChain Oracle
/// @notice
// collateral (Exogenous btc && eth)
// Miniting Algorithmic
// realative stability peppeg to usd
//This is the contract meant to be governed by dscEngine. This contract is just the Erc20 implemntation
/// @dev this contract is just the Erc20 implemntation of our stable coin system

contract DecentralizeStableCoin is ERC20Burnable, Ownable {
    error DecentralizeStableCoin__MustBeMoreThanZero();
    error DecentralizeStableCoin__BurnAmountExceedsBalance();
    error DecentralizeStableCoin__NotZeroAddress();

    constructor() ERC20("BOStableCoin", "BOSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizeStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizeStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizeStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizeStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
