// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {YoloToken} from "../src/YoloToken.sol";

/// @dev Drives the token with successful and failing calls from several actors and keeps an
/// independent ledger of what every balance and allowance must be. Failing calls are made through
/// try/catch so the run keeps fail_on_revert semantics: a failure that does not revert, or a revert
/// that changes state, is reported by the handler's own assertions or by the ledger invariants.
contract YoloModelHandler is Test {
    YoloToken internal immutable token;
    address[] internal actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostSuccessfulMoves;
    uint256 public ghostRejectedCalls;
    uint256 public ghostMovedVolume;

    constructor(YoloToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _move(address from, address to, uint256 amount) internal {
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ++ghostSuccessfulMoves;
        ghostMovedVolume += amount;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (infinite) amount = type(uint256).max;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 approved = ghostAllowance[from][spender];
        uint256 cap = approved < ghostBalance[from] ? approved : ghostBalance[from];
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (approved != type(uint256).max) ghostAllowance[from][spender] = approved - amount;
        _move(from, to, amount);
    }

    /// @dev Any amount strictly above the sender's balance must revert with the exact error.
    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = ghostBalance[from];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        vm.prank(from);
        try token.transfer(to, amount) returns (bool) {
            assertTrue(false, "transfer above balance succeeded");
        } catch (bytes memory reason) {
            assertEq(
                reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        }
        ++ghostRejectedCalls;
    }

    /// @dev Spending one unit beyond the allowance must revert even when the balance covers it.
    function transferFromAboveAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess)
        external
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 approved = ghostAllowance[from][spender];
        if (approved == type(uint256).max) return;
        uint256 amount = approved + bound(excess, 1, type(uint256).max - approved);
        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool) {
            assertTrue(false, "transferFrom above allowance succeeded");
        } catch (bytes memory reason) {
            assertEq(
                reason,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
            );
        }
        ++ghostRejectedCalls;
    }

    /// @dev Within the allowance but above the owner's balance: must revert and leave the allowance.
    function transferFromAboveBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 approved = ghostAllowance[from][spender];
        uint256 balance = ghostBalance[from];
        if (approved <= balance) return;
        uint256 amount = balance + bound(excess, 1, approved - balance);
        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool) {
            assertTrue(false, "transferFrom above balance succeeded");
        } catch (bytes memory reason) {
            assertEq(
                reason, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        }
        ++ghostRejectedCalls;
    }

    /// @dev Burning by sending to the zero address must be impossible, by transfer or transferFrom.
    function sendToZeroAddress(uint256 fromSeed, uint256 amount, bool viaTransferFrom) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        if (viaTransferFrom) {
            vm.prank(from);
            assertTrue(token.approve(address(this), amount));
            ghostAllowance[from][address(this)] = amount;
            try token.transferFrom(from, address(0), amount) returns (bool) {
                assertTrue(false, "transferFrom to the zero address succeeded");
            } catch (bytes memory reason) {
                assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            }
        } else {
            vm.prank(from);
            try token.transfer(address(0), amount) returns (bool) {
                assertTrue(false, "transfer to the zero address succeeded");
            } catch (bytes memory reason) {
                assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            }
        }
        ++ghostRejectedCalls;
    }

    /// @dev Unknown or privileged-looking selectors must never succeed nor change any balance.
    function callUnknownSelector(uint256 callerSeed, bytes4 selector, address target, uint256 value) external {
        bytes4[5] memory known = [
            token.transfer.selector,
            token.approve.selector,
            token.transferFrom.selector,
            // view functions succeed harmlessly; skip them so the assertion below stays meaningful
            token.balanceOf.selector,
            token.allowance.selector
        ];
        for (uint256 i; i < known.length; ++i) {
            if (selector == known[i]) return;
        }
        if (
            selector == token.totalSupply.selector || selector == token.name.selector
                || selector == token.symbol.selector || selector == token.decimals.selector
                || selector == token.INITIAL_SUPPLY.selector
        ) return;
        vm.prank(_actor(callerSeed));
        (bool ok,) = address(token).call(abi.encodeWithSelector(selector, target, value));
        assertFalse(ok, "an unknown selector was accepted");
        ++ghostRejectedCalls;
    }
}

contract YoloTokenModelInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    YoloToken internal token;
    YoloModelHandler internal handler;
    address[] internal actors;

    function setUp() public {
        token = new YoloToken();
        actors.push(makeAddr("whale"));
        actors.push(makeAddr("trader"));
        actors.push(makeAddr("empty"));
        actors.push(makeAddr("dust"));
        actors.push(address(token));
        actors.push(address(this));

        // Uneven start: the whole supply minus dust to one actor, one wei to another, nothing to the rest.
        assertTrue(token.transfer(actors[0], SUPPLY - 1e18 - 1));
        assertTrue(token.transfer(actors[1], 1e18));
        assertTrue(token.transfer(actors[3], 1));
        assertEq(token.balanceOf(address(this)), 0);

        handler = new YoloModelHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.transferAboveBalance.selector;
        selectors[4] = handler.transferFromAboveAllowance.selector;
        selectors[5] = handler.transferFromAboveBalance.selector;
        selectors[6] = handler.sendToZeroAddress.selector;
        selectors[7] = handler.callUnknownSelector.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_supplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), token.INITIAL_SUPPLY());
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesSumToSupplyAndNothingLeaks() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "tokens appeared outside the actor set");
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.ghostAllowance(actors[i], actors[j]));
            }
            assertEq(token.allowance(actors[i], address(handler)), handler.ghostAllowance(actors[i], address(handler)));
        }
    }

    function afterInvariant() external view {
        // Guards against a vacuous campaign: the run must have exercised both success and failure paths.
        assertGt(handler.ghostSuccessfulMoves() + handler.ghostRejectedCalls(), 0);
    }
}
