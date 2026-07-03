# Latam stables

## Installation

1. **Install Foundry** (if not already installed):

```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. **Install project dependencies:**

```
make install
```

3. **Build the project:**

```
make build
```

4. **Run tests:**

```
make test
```

## Running the Project

- To run tests: `make test`
- To build: `make build`
- To deploy: see the Deployment section below

### Setting the Wallet for Deployment

The deployment script requires a wallet address to broadcast transactions. By default, if you do not specify a network, the script uses a local Anvil account. For other networks, you can set the wallet in one of two ways:

#### 1. Using a Private Key (for local Anvil or testnets)

Set the `DEFAULT_ANVIL_KEY` environment variable in your `.env` file or shell:

```
DEFAULT_ANVIL_KEY=your_private_key_here
```

#### 2. Using a Keystore (for public networks)

Set the following environment variables in your `.env` file or shell:

```
KEYSTORE_PATH=path/to/your/keystore
KEYSTORE_PASSWORD=your_keystore_password
```

##### Importing a Wallet Key Using Cast

You can import a private key into a keystore using the following command:

```
cast wallet import --interactive key.json --keystore-dir keys
```

- This will prompt you to enter your private key and set a password.
- The generated `key.json` file will be stored in the `keys` directory.
- Set `KEYSTORE_PATH` to the path of the generated `key.json` and `KEYSTORE_PASSWORD` to the password you set.

The Makefile will automatically use these variables to determine the wallet address for deployment. For more details, see the comments in the Makefile.


## Deployment

To deploy the LatamStable contract, you need to set the following environment variables with the addresses for each role:

- `DEFAULT_ADMIN`: Address to be granted the DEFAULT_ADMIN_ROLE
- `PAUSER`: Address to be granted the PAUSER_ROLE
- `MINTER`: Address to be granted the MINTER_ROLE
- `UPGRADER`: Address to be granted the UPGRADER_ROLE
- `TOKEN_NAME`: The name of the token (e.g., "Latam Stable")
- `TOKEN_SYMBOL`: The symbol of the token (e.g., "LATAM")

You can set these in your shell or in a `.env` file in the project root.

### Example `.env` file

```
DEFAULT_ADMIN=0xYourAdminAddress
PAUSER=0xYourPauserAddress
MINTER=0xYourMinterAddress
UPGRADER=0xYourUpgraderAddress
TOKEN_NAME=Latam Stable
TOKEN_SYMBOL=LATAM
```

### Deploying with Makefile

To deploy the contract, use the following command:

```
make deploy-latam-stable 
```

You can also specify a network using the `ARGS` variable. For example, to deploy to Sepolia:

```
make deploy-latam-stable ARGS="--network sepolia"
```

This will run the deployment script using the parameters from your environment variables and print the deployed contract addresses and roles.

## Tempo TIP-20 Deployment

Tempo-native stablecoins should be created through the TIP-20 factory rather than by deploying `LatamStable` behind an ERC1967 proxy. The existing ERC1967 path remains available for non-Tempo networks.

This path creates a native TIP-20 token. It does not deploy a custom `Tip20LatamStable.sol` token contract.

### Deploy a native TIP-20 token

Set environment variables:

```env
TOKEN_NAME=Colombian Peso
TOKEN_SYMBOL=WCOP
TOKEN_CURRENCY=COP
QUOTE_TOKEN=0x20c0000000000000000000000000000000000000
TIP20_ADMIN=0xAdminAddress
TIP20_SALT=0x631063836fa5a002b22b7bd7ede381f53799ed51b75bda60adcce337f3c5d6b5
TEMPO_RPC_URL=https://rpc.tempo.xyz
MODERATO_RPC_URL=https://rpc.moderato.tempo.xyz
# Optional: TOKEN_LOGO_URI=https://example.com/token.png
```

Deploy on Tempo mainnet:

```bash
make deploy-tip20-latam-stable ARGS="--network tempo"
```

Or deploy on Moderato testnet:

```bash
make deploy-tip20-latam-stable ARGS="--network moderato"
```

The deploy script calls `TIP20Factory.createToken(...)`, logs the deterministic token address from `getTokenAddress(deployer, salt)`, verifies `QUOTE_TOKEN` with `isTIP20`, checks whether the expected token already exists, and logs the quote token's currency before broadcasting.

`TOKEN_CURRENCY` is the asset one unit of the token tracks, not the token symbol. For example, a COP-pegged token should use `COP`.

### Tempo TIP-20 limited issuance

Ripio's ERC-20 issuance flow uses `LimitedMinter` as a capped issuance control plane. The Tempo-native equivalent is `Tip20LimitedMinter`.

The target sequence is:

1. Deploy/create the native TIP-20 token.
2. Deploy `Tip20LimitedMinter`.
3. Grant the TIP-20 token's `ISSUER_ROLE` to `Tip20LimitedMinter`.
4. Register the TIP-20 token in `Tip20LimitedMinter` with a mint destination and daily cap.
5. Have the operator call `Tip20LimitedMinter.mint(...)` or `Tip20LimitedMinter.mintWithMemo(...)`, which calls the matching TIP-20 mint method.

Deploy the limited minter:

```bash
DEFAULT_ADMIN=0xAdminAddress
MINTER=0xMintOperator
TOKEN_CONFIG_ADMIN=0xConfigAdmin
make deploy-tip20-limited-minter ARGS="--network moderato"
```

Grant TIP-20 roles:

```bash
TIP20_TOKEN=0x20c...
TIP20_ISSUER=0xTip20LimitedMinter
TIP20_PAUSER=0xSecurityOps
TIP20_UNPAUSER=0xSecurityOps
TIP20_BURN_BLOCKED=0xRecoveryOps
make grant-tip20-roles ARGS="--network moderato"
```

Register the token and mint through the control plane:

```bash
TIP20_LIMITED_MINTER=0xTip20LimitedMinter
TIP20_TOKEN=0x20c...
MINT_DESTINATION=0xTreasuryOrMintDestination
DAILY_MAX_MINT=1000000000000
make register-tip20-token ARGS="--network moderato"

MINT_AMOUNT=1000000
make tip20-mint ARGS="--network moderato"
```

`MINT_MEMO` is optional. If it is unset or zero, the script uses the no-memo `mint(token, amount)` path. If it is nonzero, the script uses `mintWithMemo(token, amount, memo)`.

All TIP-20 amounts use TIP-20 units. Tempo TIP-20 tokens expose 6 decimals, while the current OZ ERC-20 path defaults to 18 decimals. Amount conversion must be handled explicitly in scripts and operational runbooks.

TIP-20 does not expose OpenZeppelin-style role read helpers such as `hasRole`. The role grant script submits role changes and relies on the precompile to enforce authorization. Role membership should be tracked from TIP-20 role events or deployment manifests.

### Tempo TIP-20 bridge support

Ripio's ERC-20 bridge path uses `BridgeDeposit` and `LimitedMinterBridge`. The Tempo-native equivalent keeps the same operational model but uses separate TIP-20 contracts:

1. `Tip20BridgeDeposit` on the source chain pulls approved TIP-20 tokens into the bridge contract, sends any fixed route fee, and burns the remainder with `burn(...)` or `burnWithMemo(...)`.
2. The offchain bridge operator observes `BridgeDepositInitiated(...)`.
3. `Tip20BridgeDeposit` on the destination chain calls `Tip20LimitedMinterBridge.mintTo(...)`.
4. `Tip20LimitedMinterBridge` enforces the registered token's daily mint cap and mints to the final recipient with `mint(...)` or `mintWithMemo(...)`.
5. `Tip20BridgeDeposit` tracks replay protection with `(sourceChainId, sourceTxHash, sourceDepositId)` and updates burn/mint accounting.

Deploy the bridge minter:

```bash
DEFAULT_ADMIN=0xAdminAddress
MINTER=0xAdminOrTemporaryMinter
TOKEN_CONFIG_ADMIN=0xConfigAdmin
make deploy-tip20-limited-minter-bridge ARGS="--network moderato"
```

Deploy the bridge deposit contract:

```bash
BRIDGE_ADMIN=0xBridgeAdmin
TIP20_LIMITED_MINTER_BRIDGE=0xTip20LimitedMinterBridge
FEE_COLLECTOR=0xFeeCollector
make deploy-tip20-bridge-deposit ARGS="--network moderato"
```

Grant the local bridge mint role:

```bash
TIP20_LIMITED_MINTER_BRIDGE=0xTip20LimitedMinterBridge
TIP20_BRIDGE_DEPOSIT=0xTip20BridgeDeposit
make grant-tip20-bridge-minter-role ARGS="--network moderato"
```

Grant TIP-20 issuer authority:

```bash
TIP20_TOKEN=0x20c...
TIP20_ISSUER=0xTip20LimitedMinterBridge
make grant-tip20-roles ARGS="--network moderato"

TIP20_TOKEN=0x20c...
TIP20_ISSUER=0xTip20BridgeDeposit
make grant-tip20-roles ARGS="--network moderato"
```

`Tip20LimitedMinterBridge` needs `ISSUER_ROLE` to mint on the destination chain. `Tip20BridgeDeposit` needs `ISSUER_ROLE` only on chains where it burns Tempo-native balances for outbound bridge deposits.

Register the token in the bridge minter and configure an outbound route:

```bash
TIP20_LIMITED_MINTER_BRIDGE=0xTip20LimitedMinterBridge
TIP20_TOKEN=0x20c...
DAILY_MAX_MINT=1000000000000
make register-tip20-bridge-token ARGS="--network moderato"

TIP20_BRIDGE_DEPOSIT=0xTip20BridgeDeposit
TIP20_TOKEN=0x20c...
DEST_CHAIN_ID=4217
ROUTE_ENABLED=true
FIXED_FEE=0
make set-tip20-bridge-route ARGS="--network moderato"
```

User deposit flow:

```bash
# User must approve Tip20BridgeDeposit for BRIDGE_AMOUNT first.
TIP20_BRIDGE_DEPOSIT=0xTip20BridgeDeposit
TIP20_TOKEN=0x20c...
BRIDGE_AMOUNT=1000000
DEST_CHAIN_ID=4217
DEST_RECIPIENT=0xRecipient
make tip20-deposit-for-bridge ARGS="--network moderato"
```

`CLIENT_DEPOSIT_ID` is optional. If it is unset or zero, the script uses the no-memo `depositForBridge(...)` path and plain TIP-20 `burn(...)`. If it is nonzero, the script uses `depositForBridgeWithMemo(...)` and TIP-20 `burnWithMemo(...)`.

Operator fulfillment flow:

```bash
TIP20_BRIDGE_DEPOSIT=0xTip20BridgeDeposit
TIP20_TOKEN=0x20c...
BRIDGE_RECIPIENT=0xRecipient
BRIDGE_AMOUNT=1000000
SOURCE_CHAIN_ID=42431
SOURCE_TX_HASH=0xSourceDepositTxHash
SOURCE_DEPOSIT_ID=1
make tip20-fulfill-bridge-mint ARGS="--network tempo"
```

`BRIDGE_MEMO` is optional. If it is unset or zero, the script uses the no-memo `fulfillBridgeMint(...)` path and plain TIP-20 `mint(...)`. If it is nonzero, the script uses `fulfillBridgeMintWithMemo(...)` and TIP-20 `mintWithMemo(...)`.

TIP-20 transfer policies and account-level receive policies still apply. The bridge contracts use balance-delta checks so receive-policy redirects or blocked deliveries revert instead of silently moving funds into recovery custody.

## Bridge Contracts

The bridge infrastructure enables cross-chain token transfers using a burn-and-mint mechanism.

### Architecture

1. **LimitedMinterBridge**: Rate-limited minting contract that enforces daily mint caps per token. Unlike `LimitedMinter`, it allows minting to arbitrary recipients (for bridge fulfillment).

2. **BridgeDeposit**: Handles both sides of cross-chain bridges:
   - **Source chain**: Users call `depositForBridge()` to burn tokens
   - **Destination chain**: Bridge operators call `fulfillBridgeMint()` to mint tokens via `LimitedMinterBridge`

### Deploying Bridge Contracts

#### 1. Deploy LimitedMinterBridge

Set environment variables:
```
DEFAULT_ADMIN=0xAdminAddress
MINTER=0xMinterAddress  # Address that can call mintTo (e.g., BridgeDeposit contract)
```

Deploy:
```
make deploy-limited-minter-bridge ARGS="--network sepolia"
```

#### 2. Deploy BridgeDeposit

Set environment variables:
```
BRIDGE_ADMIN=0xAdminAddress      # Receives DEFAULT_ADMIN_ROLE and BRIDGE_OPERATOR_ROLE
LIMITED_MINTER=0xLimitedMinterBridgeAddress  # Address from step 1
```

Deploy:
```
make deploy-bridge-deposit ARGS="--network sepolia"
```

### Post-Deployment Setup

After deploying both contracts, you need to:

1. **Grant MINTER_ROLE on LimitedMinterBridge to BridgeDeposit**:
   ```solidity
   limitedMinterBridge.grantRole(MINTER_ROLE, bridgeDepositAddress);
   ```

2. **Register tokens in LimitedMinterBridge** (by token admin):
   ```solidity
   limitedMinterBridge.registerToken(tokenAddress, dailyMaxMint);
   ```

3. **Add supported tokens to BridgeDeposit** (by admin):
   ```solidity
   bridgeDeposit.setSupportedToken(tokenAddress, true);
   ```

4. **Grant MINTER_ROLE on LatamStable to LimitedMinterBridge** (by token admin):
   ```solidity
   latamStable.grantRole(MINTER_ROLE, limitedMinterBridgeAddress);
   ```
