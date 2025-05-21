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
