# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
make build          # Build the project
make test           # Run all tests
make coverage       # Run coverage (excludes mocks)
make format         # Format Solidity code
make install        # Install dependencies (OpenZeppelin contracts, forge-std)
make anvil          # Start local Anvil chain
```

Run a single test:
```bash
forge test --match-test test_Mint -vvv
```

Run tests for a specific contract:
```bash
forge test --match-contract LatamStableTest -vvv
```

## Deployment

Deploy commands require environment variables (see README.md for full list):
```bash
make deploy-latam-stable                              # Deploy to local Anvil
make deploy-latam-stable ARGS="--network sepolia"     # Deploy to Sepolia
make deploy-limited-minter ARGS="--network base"      # Deploy LimitedMinter to Base
```

Supported networks: `ethereum`, `sepolia`, `worldchain`, `worldchain-sepolia`, `base`, `zkLatestnet`, `forked-ethereum`

## Architecture

**LatamStable** (`src/LatamStable.sol`): UUPS-upgradeable ERC20 stablecoin with:
- Access control roles: `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `MINTER_ROLE`, `UPGRADER_ROLE`
- ERC20 extensions: Burnable, Pausable, Permit
- Deployed behind an ERC1967 proxy

**LimitedMinter** (`src/LimitedMinter.sol`): Rate-limited minting contract for LatamStable tokens:
- Token admins (from the LatamStable contract) register tokens with daily mint limits
- Mints to a fixed destination address per token
- Days calculated in UTC (Unix time / 1 days)

**LimitedMinterBridge** (`src/LimitedMinterBridge.sol`): Variant of LimitedMinter for bridge operations:
- Same daily limit enforcement
- Allows minting to arbitrary recipients (no fixed destination)

**BridgeDeposit** (`src/BridgeDeposit.sol`): Bridge deposit/fulfillment contract:
- Users burn tokens via `depositForBridge` on source chain
- Operators call `fulfillBridgeMint` on destination chain (uses LimitedMinterBridge)
- Idempotency via `sourceTxHash` tracking

## Key Patterns

- Solidity 0.8.27 with optimizer (200 runs)
- OpenZeppelin upgradeable contracts for LatamStable, non-upgradeable for minter contracts
- Custom errors (not require strings)
- ReentrancyGuard + Pausable on minting contracts
- Tests use forge-std's `Test` base with `makeAddr()` for test accounts
