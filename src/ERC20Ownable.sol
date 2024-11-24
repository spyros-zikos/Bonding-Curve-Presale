// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import "@openzeppelin-npm/token/ERC20/ERC20.sol";
// import "@openzeppelin-npm/access/Ownable.sol";
// import "@openzeppelin-npm/security/Pausable.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ERC20Ownable is ERC20, Ownable {
	event TokensMinted(address indexed to, uint256 amount);
	event TokensBurned(address indexed from, uint256 amount);

	constructor(
		string memory name_,
		string memory symbol_
	) ERC20(name_, symbol_) Ownable(msg.sender) {

	}

	function mint(address to, uint256 amount) external onlyOwner {
		_mint(to, amount);
		emit TokensMinted(to, amount);
	}

	// DANGER: This function is not safe and should not be used in production, should be onlyOnwer
	function burn(address from, uint256 amount) external onlyOwner {
		_burn(from, amount);
		emit TokensBurned(from, amount);
	}
}