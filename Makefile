-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil submodules remove update build

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]"
	@echo "  example: make deploy ARGS=\"--network latestnet\""
	@echo ""
	@echo "See docs/deployment-guide.md for detailed deployment instructions"

# remove everything, re-install, update, build
all: clean remove install build

# Clean Foundry Artifacts
clean:
	forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

# Install Dependencies
install :; forge install OpenZeppelin/openzeppelin-contracts --no-commit && forge install foundry-rs/forge-std --no-commit && forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit

# Update Dependencies If Needed
update:
	forge update

# Build Project
build:
	forge build

# Test Project
test:
	forge test

# Snapshot (for differential testing)
snapshot:
	forge snapshot

# Coverage
coverage:
	forge coverage --no-match-coverage ".*mocks.*"

# Format Solidity Code
format:
	forge fmt

# Start Local Anvil Chain with a Deterministic Mnemonic
anvil:
	anvil -m "test test test test test test test test test test test junk" --steps-tracing

forked-ethereum:
	anvil -m "test test test test test test test test test test test junk" --steps-tracing --fork-url $(ETHEREUM_RPC_URL) --chain-id 7400 --base-fee 1000000000

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network ethereum,$(ARGS)),--network ethereum)
	NETWORK_ARGS := --rpc-url $(ETHEREUM_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 1600000000
	VERIFY_ARGS := --verify --chain-id 1 --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY)

else ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 8000000 
	VERIFY_ARGS := --verify --chain-id 11155111 --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY)

else ifeq ($(findstring --network worldchain-sepolia,$(ARGS)),--network worldchain-sepolia)
	NETWORK_ARGS := --rpc-url $(WORLDCHAIN_SEPOLIA_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 1000350 
	VERIFY_ARGS := --verify --chain-id 4801 --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY)

else ifeq ($(findstring --network worldchain,$(ARGS)),--network worldchain)
	NETWORK_ARGS := --rpc-url $(WORLDCHAIN_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 1009000 
	VERIFY_ARGS := --verify --chain-id 480 --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY)

else ifeq ($(findstring --network forked-ethereum,$(ARGS)),--network forked-ethereum)
	NETWORK_ARGS := --rpc-url $(FORKED_ETHEREUM_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 8000000000
	VERIFY_ARGS := 

else ifeq ($(findstring --network zkLatestnet,$(ARGS)),--network zkLatestnet)
	NETWORK_ARGS := --rpc-url $(LATESTNET_ZK_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 25000000 --skip-simulation --slow --gas-limit 10000000
	VERIFY_ARGS := --verify --chain-id 14183 --verifier custom --verifier-url $(LATESTNET_ZK_VERIFIER_URL) 

else ifeq ($(findstring --network base,$(ARGS)),--network base)
	NETWORK_ARGS := --rpc-url $(BASE_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) --broadcast --with-gas-price 2500000 
	VERIFY_ARGS := --verify --chain-id 8453 --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY)
else
	VERIFY_ARGS :=
endif

# Determine if we're using a local Anvil chain
ifeq ($(findstring --network,$(ARGS)),)
# Local Anvil deployment - use default Anvil account
WALLET_ADDRESS := $(shell cast wallet address --private-key $(DEFAULT_ANVIL_KEY))
else ifneq ($(KEYSTORE_PATH),)
# Non-local deployment with keystore - use keystore account
WALLET_ADDRESS := $(shell cast wallet address \
  --keystore $(KEYSTORE_PATH) \
  --password $(KEYSTORE_PASSWORD))
else
# Non-local deployment without keystore - fallback to default Anvil account
WALLET_ADDRESS := $(shell cast wallet address --private-key $(DEFAULT_ANVIL_KEY))
endif

# Deploy Latam Stable
deploy-latam-stable:
	@forge script script/DeployLatamStable.s.sol:DeployLatamStable $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

deploy-limited-minter:
	@forge script script/DeployLimitedMinter.s.sol:DeployLimitedMinter $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

set-limited-minter-role:
	@forge script script/SetLimitedMinterRole.s.sol:SetLimitedMinterRole $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

deploy-limited-minter-bridge:
	@forge script script/DeployLimitedMinterBridge.s.sol:DeployLimitedMinterBridge $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

deploy-bridge-deposit:
	@forge script script/DeployBridgeDeposit.s.sol:DeployBridgeDeposit $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# CREATE2 Deterministic Deployment Commands
# These commands deploy LimitedMinterBridge and BridgeDeposit with the same addresses across all chains

# Compute deterministic addresses without deploying (dry run)
compute-bridge-addresses:
	@forge script script/create2/ComputeAddresses.s.sol:ComputeAddresses --sig "run()"

# Deploy both contracts via CREATE2 (same address on all chains)
deploy-bridge-create2:
	@forge script script/create2/DeployBridgeCreate2.s.sol:DeployBridgeCreate2 $(NETWORK_ARGS) $(VERIFY_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Grant MINTER_ROLE on LimitedMinterBridge to BridgeDeposit (post-deployment)
grant-bridge-minter-role:
	@forge script script/create2/GrantMinterRole.s.sol:GrantMinterRole $(NETWORK_ARGS) --sig "run(address)" $(WALLET_ADDRESS)

# Verify deployment status on a chain
verify-bridge-deployment:
	@forge script script/create2/VerifyDeployment.s.sol:VerifyDeployment $(NETWORK_ARGS) --sig "run()"

# cast wallet import --interactive key.json --keystore-dir keys
# example command: make deploy-latam-stable ARGS="--network sepolia"
