# yolo (YOLO)

$yolo time

A fixed-supply ERC-20 for Ethereum. The description is treated as branding; it
does not specify an additional application or time-dependent behavior.

## Token behavior

| Parameter | Value |
| --- | --- |
| Solidity contract | `YoloToken` |
| Token name | `yolo` |
| Token symbol | `YOLO` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Initial recipient | The immediate constructor caller (`msg.sender`) |
| Constructor arguments | None |

The constructor mints the entire supply once and emits the standard
`Transfer(address(0), deployer, supply)` event. Supply cannot subsequently
increase or decrease. The token has no owner, minter, administrator, proxy,
upgrade mechanism, pause, blacklist, seizure, burn function, or transfer tax.
There are no allocations inside the constructor.

Transfers deliver the exact requested amount. Zero-value and self transfers
are supported. Transfers to the zero address, insufficient balances, approvals
to the zero address, and insufficient allowances revert with OpenZeppelin's
ERC-6093 errors. A reverted operation leaves balances and allowances unchanged.

`approve` sets an allowance, and `transferFrom` consumes it. An approval of
`type(uint256).max` is unlimited and is not decremented. A holder calling
`transferFrom` on their own balance still needs an allowance; `transfer` is
the direct holder operation. Approvals emit `Approval`, and transfers emit
`Transfer`. OpenZeppelin 5.0.2 does not emit a new `Approval` event when
`transferFrom` spends an allowance; integrations should read `allowance`.

## Build and test

Requires Foundry and Solidity **0.8.26**. The compiler is pinned by version in
`foundry.toml`, with the Cancun EVM target, optimizer enabled at 200 runs, and
`bytecode_hash = "none"`. These settings are part of the deployment build.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x83b69b607cdac0b7c6636954e6893309f12baa2a224200f42195e601d1c14dd4 forge test
forge fmt --check
```

All Solidity dependencies are vendored as ordinary files in `lib/`, including
their licenses. No package install, submodule, RPC, credentials, environment
configuration, FFI, or filesystem permissions are needed by the tests. Once
Foundry and the pinned compiler are installed, builds and tests work without
network access. The shell seed above controls reproducibility; tests themselves
do not read or modify environment variables.

The unit tests cover metadata, the single mint event, complete initial supply,
CREATE2 deployment by a factory, transfer and approval events, zero and self
transfers, exact amounts, finite and infinite allowances, revocation,
unauthorized spending, invalid recipients, insufficient funds, failure
rollback, and rejection of common administrative calls.

Four fuzz tests run 1,000 cases each. A stateful invariant test runs 128
sequences of 64 actions across four holders, checking exact transfer accounting,
allowance consumption, and preservation of both total supply and aggregate
balances after interleaved transfers, approvals, and delegated transfers.

The local launch-flow test exercises exact token movements for distribution,
claims, and transfers to and from a pool-manager actor. It does not implement
Uniswap swaps. The supplied protected harness performs the actual pool
initialization, seed, and swap integration checks in the launch environment;
that external infrastructure is not part of this repository.

## Deployment parameters and responsibilities

Deploy the compiled creation bytecode for `src/YoloToken.sol:YoloToken`, with
**no ABI-encoded constructor arguments** and no ETH value. There is no
initializer, external constructor call, linked library, or post-deployment
configuration. The intended chain is Ethereum mainnet (chain ID 1).

For the IdentityMD custom launch, the factory creates the token and therefore
receives all `10^27` units. The originating wallet and requester do not receive
tokens directly from this constructor. The factory performs the launch
distribution afterward: 10% to the swarm distributor, 60% to pool seeding, and
the remaining 30% to the requester destination specified in the launch terms.
Those destinations, pool parameters, and economics belong to the launch
infrastructure and manifest; the token contains no address guesses or
allocation logic.

The launch operator is responsible for using the intended factory, recording
the exact name, symbol, decimals, supply, and empty constructor argument list,
performing distribution and pool initialization, and verifying the deployed
source and bytecode. The separate manifest step supplies `launch.json`. This
project does not broadcast transactions or manage a signing key.

## After launch

There are no owner settings, keepers, or administrative transactions. Holders
control their balances and allowances. Applications should check transfer
results, use the 18-decimal unit scale, and query current allowances.

Holders are responsible for choosing trusted spenders and recipients. Prefer
bounded approvals. When replacing an existing nonzero allowance, revoke it
first and wait for confirmation before setting the replacement to reduce the
standard ERC-20 allowance transaction-ordering risk.

The contract has no recovery function. Tokens sent to this token contract or
another contract unable to transfer them may be permanently inaccessible.
Direct ETH payments revert. The deployer has no special ability to recover
tokens, reverse transfers, freeze balances, or repair deployed code.

## Review scope

The production implementation is a small constructor-only extension of the
vendored OpenZeppelin ERC-20. Token operations make no external calls, consume
no oracle data, use no randomness or signatures, and have no privileged paths.
The supplied security reference was reviewed for applicable failure modes.
Local validation uses Solidity compilation, Foundry unit/fuzz/invariant tests,
and formatting checks. Slither and Mythril were not run. This work is not an
independent security audit; the launch's separate adversarial review and
deployment verification remain the launch operator's responsibilities.

Dependency versions, upstream locations, and integrity verification are
documented in [lib/README.md](lib/README.md).
