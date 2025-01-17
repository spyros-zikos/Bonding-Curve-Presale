// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev ERC20 with Ownable
 * @dev Should be used only from the bonding curve contract
 * because it overrides the transferFrom function
 */
contract ERC20Ownable is ERC20, Ownable {
	address private i_bondingCurve;

	event TokensMinted(address indexed to, uint256 amount);
	event TokensBurned(address indexed from, uint256 amount);

	constructor(
		string memory name,
		string memory symbol
	) ERC20(name, symbol) Ownable(msg.sender) {
		i_bondingCurve = msg.sender;
	}

	function mint(address to, uint256 amount) external onlyOwner {
		_mint(to, amount);
		emit TokensMinted(to, amount);
	}

	function burn(address from, uint256 amount) external onlyOwner {
		_burn(from, amount);
		emit TokensBurned(from, amount);
	}

	// override
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        address spender = _msgSender();
        if (spender != i_bondingCurve)
            _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

	function getBondingCurve() external view returns (address) {
		return i_bondingCurve;
	}
}