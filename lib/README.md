# Vendored dependencies

All dependency code is included as ordinary files. No submodules, package
manager downloads, or external library links are required.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `v5.0.2` | `ERC20.sol` and its four transitive Solidity dependencies | MIT |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | Upstream `src/` tree; test dependency only | MIT or Apache-2.0 |

The source files are unmodified snapshots from the respective release
archives. Licenses are retained inside each dependency directory.
`remappings.txt` resolves imports to these local sources.

Verify every vendored source and license against the recorded hashes from the
repository root:

```sh
sha256sum -c lib/SHA256SUMS
```

Compiler and Foundry binaries are toolchain prerequisites and are not vendored.
