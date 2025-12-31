# Project Audit Context – LatamStable Bridge System (v2)

## Project Overview

The `LatamStable` project is a stablecoin infrastructure designed for Latin American markets, featuring a bridgeable ERC20 token with rate-limited minting controls. The system consists of four main contracts:

- **LatamStable**: UUPS-upgradeable ERC20 stablecoin with role-based access control (minting, pausing, upgrading)
- **LimitedMinter**: Enforces daily minting caps for registered tokens, minting to a fixed destination address per token
- **LimitedMinterBridge**: Variant of LimitedMinter that allows minting to arbitrary recipients (for bridge operations)
- **BridgeDeposit**: Handles cross-chain bridging via burn-on-source and mint-on-destination pattern with idempotency protection and **fixed per-route fees**

The system:

- Issues ERC20 stablecoins with standard burnable, pausable, and permit extensions
- Enforces daily minting limits calculated in UTC (Unix time / 1 days boundaries)
- Supports cross-chain bridging where users burn tokens on the source chain and operators mint on the destination chain
- **Collects fixed fees per route on the deposit (burn) side, transferred to a fee collector address**
- Implements idempotency via composite key (sourceChainId + sourceTxHash + sourceDepositId) to prevent double-minting
- Provides admin controls for token registration, limit configuration, route fees, and emergency pausing

## Assumptions

- The protocol will be deployed on EVM-compatible networks (Ethereum, Base, World Chain, etc.)
- LatamStable tokens implement OpenZeppelin's AccessControl pattern with `hasRole`, `DEFAULT_ADMIN_ROLE`, and `mint` functions
- Token admins (on the LatamStable contract) are trusted entities who register tokens and configure limits
- Bridge operators are trusted off-chain services that observe deposits and call `fulfillBridgeMint`
- Admin, operator, fee manager, and minter roles are controlled by secure multi-sig wallets in production
- The LimitedMinter/LimitedMinterBridge contracts must be granted `MINTER_ROLE` on LatamStable tokens they control
- Block timestamps are reasonably accurate (within expected drift for UTC day boundaries)
- **Fee collector address must be set when routes have non-zero fees configured**

## Audit Scope

The primary targets of this audit are:

- `src/LatamStable.sol`
- `src/LimitedMinter.sol`
- `src/LimitedMinterBridge.sol`
- `src/BridgeDeposit.sol` **(significant changes)**

Specifically examining:

- Daily minting limit enforcement and day boundary calculations
- Token registration/unregistration flows and configuration updates
- Bridge deposit (burn) and fulfillment (mint) flows
- **Fixed fee collection on deposit side (source chain)**
- **Route configuration with per-route fees**
- Idempotency protection via composite key (sourceChainId + sourceTxHash + sourceDepositId)
- Access control across external admin checks and internal roles
- **FEE_MANAGER_ROLE for route fee updates**
- Reentrancy protections and pause semantics
- Upgradeability of LatamStable (UUPS pattern)
- Role delegation between contracts (e.g., BridgeDeposit → LimitedMinterBridge → LatamStable)

Supporting files (tests) are in scope only insofar as they help understand intended behavior:

- `test/LatamStable.t.sol`
- `test/LimitedMinter.t.sol`
- `test/LimitedMinterBridge.t.sol`
- `test/BridgeDeposit.t.sol`

## Key Areas to Focus

1. **Fixed Fee Implementation (NEW)**
   - Fee is collected on deposit (source chain), not on mint (destination chain)
   - Fee is transferred via `safeTransferFrom` to `feeCollector` before burning
   - Validation that `amount > fixedFee` (reverts with `AmountTooLowForFee`)
   - Revert if `fixedFee > 0` but `feeCollector == address(0)`
   - `totalFeesCollected` mapping tracks fees per token per destination chain
   - Fee amount emitted in `BridgeDepositInitiated` event for reconciliation

2. **Route Configuration (NEW)**
   - `RouteConfig` struct contains `enabled` (bool) and `fixedFee` (uint256)
   - `routeConfigs[token][destChainId]` replaces old boolean `bridgeRoutes` mapping
   - `setBridgeRoutes` now takes `fixedFee` parameter
   - `updateRouteFee` allows `FEE_MANAGER_ROLE` to change fee without disabling route

3. **Daily Minting Limit Enforcement**
   - Correctness of `mintedPerDay` tracking using `block.timestamp / 1 days`
   - Edge cases at day boundaries (midnight UTC transitions)
   - Overflow/underflow in limit calculations
   - Persistence of `mintedPerDay` across token unregistration and re-registration

4. **Access Control & Role Management**
   - External admin validation via `onlyExternalAdmin` modifier (calls external token's `hasRole`)
   - Internal role management (`MINTER_ROLE`, `BRIDGE_OPERATOR_ROLE`, `FEE_MANAGER_ROLE`, `DEFAULT_ADMIN_ROLE`)
   - Role chaining: BridgeDeposit → LimitedMinterBridge → LatamStable
   - **FEE_MANAGER_ROLE can update fees but cannot enable/disable routes**
   - Potential for role misconfiguration or privilege escalation

5. **Bridge Security & Idempotency**
   - Composite key `keccak256(sourceChainId, sourceTxHash, sourceDepositId)` for idempotency
   - Prevention of double-minting from the same source transaction
   - Same-chain deposit/fulfillment prevention (defense-in-depth)
   - Trust assumptions on bridge operators

6. **Token Registration & Configuration**
   - Validation when registering tokens (zero address checks, duplicate registration)
   - Configuration updates (`updateDailyMintLimit`, `updateMintDestination`)
   - Token support synchronization between BridgeDeposit routes and LimitedMinterBridge registration
   - Impact of unregistering a token mid-operation

7. **Reentrancy & Pause Protections**
   - Correct placement of `nonReentrant` modifier on state-changing functions
   - `whenNotPaused` enforcement on critical paths
   - Behavior when contracts are paused mid-bridge-operation
   - **Order of operations in `depositForBridge`: fee transfer before burn**

8. **Upgradeability (LatamStable)**
   - Correct use of `UUPSUpgradeable` and `_authorizeUpgrade`
   - Storage layout safety with OpenZeppelin upgradeable contracts
   - Role protection on upgrade function (`UPGRADER_ROLE`)

9. **Cross-Contract Interactions**
   - Trust in external token contracts' `mint` and `burnFrom` implementations
   - **Trust in token's `transferFrom` for fee collection (uses SafeERC20)**
   - Handling of failed external calls (reverts, gas limits)
   - Consistency between `routeConfigs` in BridgeDeposit and token registration in LimitedMinterBridge

## Recent Changes (v2)

This version introduces significant changes to the fee mechanism in BridgeDeposit:

### BridgeDeposit Changes

1. **Fixed Fee Per Route**
   - Fee is now collected on the deposit (source) side, not the mint (destination) side
   - Each route (token + destChainId) has a configurable `fixedFee`
   - Fee is transferred to `feeCollector` before burning remaining amount

2. **New Structs & Mappings**
   - `RouteConfig { bool enabled; uint256 fixedFee; }` struct
   - `routeConfigs[token][destChainId]` replaces `bridgeRoutes[token][destChainId]`
   - `totalFeesCollected[token][destChainId]` for fee accounting

3. **New Role: FEE_MANAGER_ROLE**
   - Can call `updateRouteFee()` to change fees on enabled routes
   - Cannot enable/disable routes (that requires DEFAULT_ADMIN_ROLE)

4. **Updated Functions**
   - `setBridgeRoutes(token, destChainIds[], enabled, fixedFee)` - now takes fixedFee
   - `updateRouteFee(token, destChainId, newFixedFee)` - new function for fee updates
   - `depositForBridge()` - now handles fee transfer and burns `amount - fee`
   - `fulfillBridgeMint()` - simplified, no longer handles fees

5. **Updated Events**
   - `BridgeDepositInitiated` now includes `fee` parameter
   - `BridgeMintFulfilled` no longer includes `fee` parameter
   - `BridgeRoutesUpdated` now includes `fixedFee` parameter
   - New `RouteFeeUpdated` event

6. **New/Updated Errors**
   - `AmountTooLowForFee` replaces `FeeExceedsAmount`

7. **Security Hardening**
   - Defense-in-depth: `depositForBridge` checks `destChainId != block.chainid`
   - `rescueTokens` now uses `safeTransfer` instead of `transfer`
   - Fee collection requires `feeCollector != address(0)` when `fixedFee > 0`

### Unchanged Contracts
- **LatamStable**: No changes
- **LimitedMinter**: No changes
- **LimitedMinterBridge**: No changes

## Known Issues or Concerns

These are known areas of concern to be validated during the audit:

1. **Day Boundary Timing**
   - Minting limits reset at UTC midnight; users could potentially batch large mints at day boundaries if not rate-limited elsewhere.

2. **`mintedPerDay` Persistence**
   - The `mintedPerDay` mapping persists even if a token is unregistered and re-registered. This is intentional but could cause confusion if admins expect a fresh start.

3. **External Admin Check Trust**
   - The `onlyExternalAdmin` modifier trusts that the external token's `hasRole` function is correctly implemented and not manipulable.

4. **Bridge Operator Trust**
   - `BRIDGE_OPERATOR_ROLE` holders can mint arbitrary amounts (up to daily limits) to any address. Security depends heavily on off-chain operational controls.

5. **Route vs Token Registration Synchronization**
   - A route can be enabled in BridgeDeposit but the token not registered in LimitedMinterBridge (or vice versa), potentially causing failed operations. Admin validation is required.

6. **Fee Collection Requires feeCollector (NEW)**
   - If a route has `fixedFee > 0` but `feeCollector` is `address(0)`, deposits will revert. This is intentional but admins must ensure `feeCollector` is set before configuring fees.

7. **User Approval Requirements (NEW)**
   - Users must approve BridgeDeposit for the full `amount` (fee + burn amount), as two allowance-consuming operations occur: `transferFrom` for fee and `burnFrom` for remainder.

8. **Block Timestamp Manipulation**
   - Day calculations rely on `block.timestamp`. Minor manipulation by miners is possible but unlikely to significantly impact daily limits.

## Out of Scope

- Frontend, integration SDKs, and indexer code
- Off-chain bridge operator infrastructure and monitoring
- Governance contracts or DAO mechanisms
- Third-party token implementations that may be registered
- Deployment tooling and scripting beyond understanding roles and initialization
- Gas optimization (unless security-impacting)

## Protocol Details

- **Token Model:** Standard ERC20 with extensions (Burnable, Pausable, Permit) using OpenZeppelin's upgradeable contracts

- **Minting Flow (LimitedMinter):**
  - Token admin registers token with `mintDestination` and `dailyMaxMint`
  - Minter calls `mint(token, amount)` → tokens minted to fixed destination
  - Daily limit enforced via `mintedPerDay[token][currentDay]`

- **Minting Flow (LimitedMinterBridge):**
  - Token admin registers token with `dailyMaxMint` (no fixed destination)
  - Minter calls `mintTo(token, to, amount)` → tokens minted to arbitrary recipient
  - Same daily limit enforcement

- **Bridge Flow (BridgeDeposit) - UPDATED:**
  - Source chain: User calls `depositForBridge(token, amount, destChainId, destRecipient, clientDepositId)`
    - Validates `amount > fixedFee` for the route
    - Transfers `fixedFee` to `feeCollector` via `safeTransferFrom` (if fee > 0)
    - Burns `amount - fixedFee` via `burnFrom(msg.sender, amountToBurn)`
    - Emits `BridgeDepositInitiated(depositId, token, from, amountBurned, fee, destChainId, destRecipient, clientDepositId)`
  - Destination chain: Operator calls `fulfillBridgeMint(token, to, amount, sourceChainId, sourceTxHash, sourceDepositId)`
    - Checks composite key for idempotency
    - Calls `limitedMinter.mintTo(token, to, amount)`
    - Emits `BridgeMintFulfilled(token, to, amount, sourceChainId, sourceTxHash, sourceDepositId)`

- **Fee Flow (NEW):**
  - Admin sets route with `setBridgeRoutes(token, [chainIds], true, fixedFee)`
  - Fee manager can update fee with `updateRouteFee(token, destChainId, newFee)`
  - On deposit: fee transferred to `feeCollector`, remainder burned
  - `totalFeesCollected[token][destChainId]` tracks cumulative fees
  - Conservation: `totalBurnedTo` tracks only burned amount (excludes fees)

- **Roles:**
  - **LatamStable:**
    - `DEFAULT_ADMIN_ROLE`: Manages all roles
    - `PAUSER_ROLE`: Can pause/unpause token transfers
    - `MINTER_ROLE`: Can mint new tokens
    - `UPGRADER_ROLE`: Can upgrade the implementation
  - **LimitedMinter / LimitedMinterBridge:**
    - `DEFAULT_ADMIN_ROLE`: Can pause/unpause the contract
    - `MINTER_ROLE`: Can call mint functions
    - External token admins: Can register/configure tokens
  - **BridgeDeposit:**
    - `DEFAULT_ADMIN_ROLE`: Can pause/unpause, manage routes, update LimitedMinter, set feeCollector, rescue tokens
    - `BRIDGE_OPERATOR_ROLE`: Can call `fulfillBridgeMint`
    - `FEE_MANAGER_ROLE`: Can call `updateRouteFee` on enabled routes **(NEW)**

- **Security Mechanisms:**
  - `ReentrancyGuard` on all mint and bridge functions
  - `Pausable` for emergency stops
  - Custom errors for gas-efficient reverts
  - Idempotency via composite key tracking
  - SafeERC20 for token transfers
  - Defense-in-depth same-chain checks

## Deployment Information

- **Target Networks:** EVM-compatible networks (Ethereum, Sepolia, Base, World Chain, World Chain Sepolia)
- **Solidity Version:** `0.8.27` (pinned in `foundry.toml`)
- **Optimizer:** Enabled with 200 runs
- **Upgradeability:** UUPS proxy pattern for LatamStable only; minter contracts are non-upgradeable
- **Dependencies:**
  - OpenZeppelin Contracts Upgradeable (for LatamStable)
  - OpenZeppelin Contracts (for LimitedMinter, LimitedMinterBridge, BridgeDeposit)
- **License:** MIT

## Previous Audits

- Initial audit completed for v1 of the LatamStable bridge system
- This audit request covers v2 changes focused on the fixed fee implementation in BridgeDeposit

## Additional Notes

- The protocol is intended for real value (stablecoins), so assumptions about operator and admin trust need to be challenged during audit.
- The audit should focus not only on low-level bugs (reentrancy, overflows) but also on **trust assumptions**, **access control chains**, and **failure modes** of the bridge operator flow.
- **The fee mechanism introduces new attack surfaces: fee collector manipulation, fee-related DoS, and conservation accounting.**
- Future extensions (additional token support, governance, timelocks) are planned; auditors should highlight any design decisions that might limit safe extensibility.
- The `clientDepositId` in `depositForBridge` is for off-chain correlation only and has no on-chain significance.

---

## Contract Interaction Diagram (Updated)

```
                                    USERS
                                      │
                    ┌─────────────────┴─────────────────┐
                    │                                   │
                    ▼                                   ▼
            [LatamStable]                        [BridgeDeposit]
            (ERC20 Token)                    (Bridge Entry Point)
                    ▲                                   │
                    │                                   │ depositForBridge
                    │ mint()                            │ (transfers fee, burns rest)
                    │                                   │
                    │                           ┌───────┴───────┐
                    │                           │               │
                    │                           ▼               ▼
        ┌───────────┴───────────┐        [feeCollector]   BRIDGE OPERATOR
        │                       │        (receives fees)  (Off-chain Service)
        ▼                       ▼                               │
  [LimitedMinter]     [LimitedMinterBridge]                     │ fulfillBridgeMint
  (Fixed Destination)  (Arbitrary Recipient)                    │
        │                       ▲                               │
        │                       │                               │
        │                       └───────────────────────────────┘
        │                               mintTo()
        ▼
   TREASURY / HOT WALLET
```

---

## Fee Flow Diagram (NEW)

```
User deposits 100 tokens with fixedFee = 2:

    User Balance: 100 tokens (approved to BridgeDeposit)
                    │
                    ▼
            depositForBridge(token, 100, destChainId, recipient, clientId)
                    │
                    ├─── safeTransferFrom(user, feeCollector, 2) ──► feeCollector: +2 tokens
                    │
                    └─── burnFrom(user, 98) ──► Token supply: -98 tokens
                    │
                    ▼
            emit BridgeDepositInitiated(id, token, user, 98, 2, destChainId, recipient, clientId)
                    │
                    ▼
            [Off-chain operator observes event]
                    │
                    ▼
            fulfillBridgeMint(token, recipient, 98, sourceChainId, txHash, depositId)
                    │
                    ▼
            limitedMinter.mintTo(token, recipient, 98) ──► recipient: +98 tokens

Conservation: 98 burned on source = 98 minted on destination (fees excluded)
```

---

## Important: DO NOT REPORT THE FOLLOWING

### Already Addressed / By Design

1. **`mintedPerDay` Persistence Across Unregistration**
   - **Observation:** The `mintedPerDay` mapping persists even if a token is unregistered and re-registered.
   - **Status:** This is intentional behavior. Re-registering a token on the same day should not reset the daily limit to prevent abuse.

2. **No Token Rescue Mechanism in Minter Contracts**
   - **Observation:** Tokens accidentally sent to LimitedMinter/LimitedMinterBridge cannot be recovered.
   - **Status:** Acknowledged as a design choice. These contracts are not intended to hold tokens; they only facilitate minting.
   - **Note:** BridgeDeposit now has `rescueTokens()` function using SafeERC20.

3. **External Admin Check Assumes Correct Token Implementation**
   - **Observation:** `onlyExternalAdmin` modifier trusts the external token's `hasRole` implementation.
   - **Status:** By design. Only tokens implementing OpenZeppelin's AccessControl pattern should be registered.

4. **Bridge Operator Can Mint to Any Address**
   - **Observation:** BRIDGE_OPERATOR_ROLE can call `fulfillBridgeMint` with any `to` address.
   - **Status:** This is required for bridge functionality. Operational security (multi-sig, monitoring) must be in place.

5. **No On-Chain Validation of `destChainId` Value**
   - **Observation:** In `depositForBridge`, `destChainId` value is not validated for correctness (e.g., existing chain).
   - **Status:** Validation is performed off-chain by the bridge operator. Same-chain deposits are now prevented on-chain.

6. **`clientDepositId` Not Enforced Unique**
   - **Observation:** The `clientDepositId` parameter in `depositForBridge` is not validated for uniqueness.
   - **Status:** This is an optional client-provided correlation ID; uniqueness is not required on-chain.

7. **Fee Requires feeCollector to Be Set (NEW)**
   - **Observation:** Deposits with `fixedFee > 0` revert if `feeCollector == address(0)`.
   - **Status:** This is intentional. Fees must have a valid recipient; otherwise the route should have zero fee.

8. **FEE_MANAGER_ROLE Cannot Create/Disable Routes (NEW)**
   - **Observation:** FEE_MANAGER_ROLE can only update fees, not create or disable routes.
   - **Status:** By design. Route management is admin-only; fee updates are more operational.

