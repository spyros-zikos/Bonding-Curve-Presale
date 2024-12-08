// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ERC20Ownable is ERC20, Ownable {
	event TokensMinted(address indexed to, uint256 amount);
	event TokensBurned(address indexed from, uint256 amount);

	constructor(
		string memory name,
		string memory symbol
	) ERC20(name, symbol) Ownable(msg.sender) {}

	function mint(address to, uint256 amount) external onlyOwner {
		_mint(to, amount);
		emit TokensMinted(to, amount);
	}

	function burn(address from, uint256 amount) external onlyOwner {
		_burn(from, amount);
		emit TokensBurned(from, amount);
	}
}