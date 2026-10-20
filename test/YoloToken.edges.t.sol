// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {YoloToken} from "../src/YoloToken.sol";

/// @dev Deploys the token and pushes the launch flows in one call, as the factory does in one transaction.
contract OneCallLauncher {
    function launch(address distributor, address pool, address requester, uint256 poolBps)
        external
        returns (YoloToken token)
    {
        token = new YoloToken();
        uint256 supply = token.totalSupply();
        uint256 swarm = supply / 10;
        uint256 seeded = supply * poolBps / 10_000;
        require(token.transfer(distributor, swarm), "swarm");
        require(token.transfer(pool, seeded), "pool");
        require(token.transfer(requester, token.balanceOf(address(this))), "remainder");
    }
}

/// @dev A contract holder that spends on its own behalf and as a delegate.
contract ContractHolder {
    function send(YoloToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function pull(YoloToken token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

contract YoloTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    YoloToken internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    function setUp() public {
        token = new YoloToken();
    }

    function testSupplyIsExactlyTenToTheTwentySeven() public view {
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.totalSupply() / 10 ** token.decimals(), 1_000_000_000);
        assertEq(token.totalSupply() % 10 ** token.decimals(), 0);
    }

    function testOneCallLaunchFlowsArriveWhole(uint256 poolBps) public {
        poolBps = bound(poolBps, 0, 9_000);
        OneCallLauncher launcher = new OneCallLauncher();
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address requester = makeAddr("requester");
        YoloToken launched = launcher.launch(distributor, pool, requester, poolBps);
        uint256 seeded = SUPPLY * poolBps / 10_000;
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(pool), seeded);
        assertEq(launched.balanceOf(requester), SUPPLY - SUPPLY / 10 - seeded);
        assertEq(launched.balanceOf(address(launcher)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testEachDeploymentIsIndependent() public {
        YoloToken second = new YoloToken();
        assertTrue(token.transfer(alice, 1));
        assertEq(second.balanceOf(alice), 0);
        assertEq(second.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply() + second.totalSupply(), 2 * SUPPLY);
    }

    function testOneWeiBoundaryOnBalance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        token.transfer(bob, 2);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        assertEq(token.balanceOf(bob), 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function testExactAllowanceIsFullyConsumedThenRejected() public {
        assertTrue(token.approve(spender, 7));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 7));
        assertEq(token.allowance(address(this), spender), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function testAllowanceOneBelowMaxIsFinite() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
    }

    function testInfiniteAllowanceStillBoundedByBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
    }

    function testAllowancesAreDirectionalAndPerOwner() public {
        assertTrue(token.transfer(alice, 100));
        vm.prank(alice);
        assertTrue(token.approve(bob, 50));
        assertEq(token.allowance(alice, bob), 50);
        assertEq(token.allowance(bob, alice), 0);

        // bob's allowance over alice does not extend to alice's allowance over bob or to anyone else
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(bob, alice, 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(address(this), bob, 1);
    }

    function testSelfApprovalStillGatesTransferFrom() public {
        assertTrue(token.approve(address(this), 5));
        assertTrue(token.transferFrom(address(this), alice, 5));
        assertEq(token.allowance(address(this), address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function testTokensSentToTheTokenContractAreUnrecoverable() public {
        // There is no rescue function; tokens sent here stay here but remain counted in the supply.
        assertTrue(token.transfer(address(token), 3));
        assertEq(token.balanceOf(address(token)), 3);
        assertEq(token.totalSupply(), SUPPLY);
        (bool ok,) = address(token).call(abi.encodeWithSignature("rescue(address,uint256)", address(this), 3));
        assertFalse(ok);
        (ok,) = address(token).call(abi.encodeWithSignature("withdraw()"));
        assertFalse(ok);
        assertEq(token.balanceOf(address(token)), 3);
    }

    function testContractHoldersSendAndSpend() public {
        ContractHolder holder = new ContractHolder();
        assertTrue(token.transfer(address(holder), 10));
        assertTrue(holder.send(token, alice, 4));
        assertEq(token.balanceOf(address(holder)), 6);

        vm.prank(alice);
        assertTrue(token.approve(address(holder), 4));
        assertTrue(holder.pull(token, alice, bob, 4));
        assertEq(token.balanceOf(bob), 4);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(holder), 0, 1));
        holder.pull(token, alice, bob, 1);
    }

    function testRejectsEtherAndUnknownCalldata() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok, "plain ether accepted");
        vm.prank(alice);
        (ok,) = address(token).call{value: 1}(hex"deadbeef");
        assertFalse(ok, "unknown calldata accepted");
        vm.prank(alice);
        (ok,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (bob, 0)));
        assertFalse(ok, "non-payable transfer accepted ether");
        assertEq(address(token).balance, 0);
    }

    function testRejectsPermitAndOtherExtensions() public {
        bytes[] memory calls = new bytes[](5);
        calls[0] = abi.encodeWithSignature(
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
            alice,
            bob,
            1,
            block.timestamp,
            uint8(27),
            bytes32(0),
            bytes32(0)
        );
        calls[1] = abi.encodeWithSignature("increaseAllowance(address,uint256)", bob, 1);
        calls[2] = abi.encodeWithSignature("decreaseAllowance(address,uint256)", bob, 1);
        calls[3] = abi.encodeWithSignature("delegate(address)", bob);
        calls[4] = abi.encodeWithSignature("renounceOwnership()");
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok);
        }
        assertEq(token.allowance(alice, bob), 0);
    }

    function testFuzzApproveIsLastWriteWins(uint256 first, uint256 second) public {
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(spender, second));
        assertEq(token.allowance(address(this), spender), second);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzzTransferRoundTripRestoresBalances(address to, uint256 amount) public {
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        uint256 toBefore = token.balanceOf(to);
        assertTrue(token.transfer(to, amount));
        vm.prank(to);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(to), toBefore);
    }

    function testFuzzTransferFromAboveBalanceWithinAllowanceReverts(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzzSplitTransfersConserve(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, SUPPLY - a);
        assertTrue(token.transfer(alice, a));
        assertTrue(token.transfer(bob, b));
        assertEq(token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY - a - b);
    }
}
