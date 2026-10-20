// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title yolo (YOLO)
/// @notice $yolo time. One billion tokens, minted once to the deploying caller.
/// @dev A plain, immutable ERC-20 with 18 decimals and no administrative powers.
contract YoloToken is ERC20 {
    /// @notice The entire supply in the token's smallest units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev During the custom launch, msg.sender is the launch factory.
    constructor() ERC20("yolo", "YOLO") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
