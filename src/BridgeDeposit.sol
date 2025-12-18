// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILatamStableBurnable {
    function burnFrom(address account, uint256 amount) external;
}

interface ILimitedMinterBridge {
    function mintTo(address token, address to, uint256 mintAmount) external;
    function mintedToday(address token) external view returns (uint256);
    function tokenConfigs(address token) external view returns (uint256 dailyMaxMint, bool exists);
}

/**
 * @title BridgeDeposit
 * @notice Handles deposit (burn) side of the bridge on the source chain and
 *         mint side on the destination chain via LimitedMinterBridge.
 *
 * @dev
 *  - Users call `depositForBridge` to burn tokens on the source chain.
 *  - Off-chain bridge operator observes deposits and, on the destination chain,
 *    calls `fulfillBridgeMint` which in turn calls `LimitedMinterBridge.mintTo`.
 *
 *  Security / Roles:
 *  - DEFAULT_ADMIN_ROLE: can pause/unpause, manage supported tokens, and update LimitedMinterBridge.
 *  - BRIDGE_OPERATOR_ROLE: allowed to call `fulfillBridgeMint`.
 *  - This contract itself must have MINTER_ROLE on LimitedMinterBridge in order to call `mintTo`.
 */
contract BridgeDeposit is AccessControlEnumerable, ReentrancyGuard, Pausable {
    bytes32 public constant BRIDGE_OPERATOR_ROLE = keccak256("BRIDGE_OPERATOR_ROLE");

    /// @notice LimitedMinterBridge instance used for minting on this chain
    ILimitedMinterBridge public limitedMinter;

    /// @notice Outbound bridge routes: token => destChainId => enabled
    /// @dev Controls which tokens can be deposited (burned) to which destination chains
    mapping(address => mapping(uint256 => bool)) public bridgeRoutes;

    /// @notice Incremental ID for deposits initiated on this chain (local use / UI)
    uint256 public nextDepositId = 1;

    /// @notice Tracks whether a given bridge fulfillment has already been processed
    /// @dev Keyed by keccak256(sourceChainId, sourceTxHash, sourceDepositId)
    mapping(bytes32 => bool) public bridgeFulfilled;

    /// @notice Total burned per token per destination chain (outbound)
    /// @dev Used for cross-chain conservation auditing
    mapping(address => mapping(uint256 => uint256)) public totalBurnedTo;

    /// @notice Total minted per token per source chain (inbound)
    /// @dev Used for cross-chain conservation auditing
    mapping(address => mapping(uint256 => uint256)) public totalMintedFrom;

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    error ZeroAddress();
    error AmountZero();
    error InvalidRecipient();
    error BridgeAlreadyFulfilled();
    error TokenNotRegisteredInMinter();
    error InvalidSourceChain();
    error InvalidRoute();

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /**
     * @notice Emitted when a user initiates a bridge deposit (burn) on this chain
     * @param depositId Sequential deposit ID local to this contract
     * @param token Address of the token being bridged
     * @param from Address of the user who burned the tokens
     * @param amount Amount burned
     * @param destChainId Destination chain ID
     * @param destRecipient Recipient on the destination chain
     * @param clientDepositId Optional client-provided ID for off-chain correlation
     */
    event BridgeDepositInitiated(
        uint256 indexed depositId,
        address indexed token,
        address indexed from,
        uint256 amount,
        uint256 destChainId,
        address destRecipient,
        bytes32 clientDepositId
    );

    /**
     * @notice Emitted when a cross-chain bridge is fulfilled (mint) on this chain
     * @param token Address of the token being minted
     * @param to Recipient on this chain
     * @param amount Amount minted
     * @param sourceChainId Chain ID where the original burn/deposit occurred
     * @param sourceTxHash Transaction hash of the source-chain deposit (for auditability)
     * @param sourceDepositId Deposit ID from the source chain's BridgeDepositInitiated event
     */
    event BridgeMintFulfilled(
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 sourceChainId,
        bytes32 sourceTxHash,
        uint256 indexed sourceDepositId
    );

    /// @notice Emitted when outbound bridge routes are updated
    event BridgeRoutesUpdated(address indexed token, uint256[] destChainIds, bool enabled);

    /// @notice Emitted when LimitedMinterBridge reference is updated
    event LimitedMinterUpdated(address indexed oldMinter, address indexed newMinter);

    /// @notice Emitted when tokens are rescued from the contract
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    /**
     * @param admin Address that receives DEFAULT_ADMIN_ROLE and BRIDGE_OPERATOR_ROLE
     * @param _limitedMinter Address of the LimitedMinterBridge contract on this chain
     */
    constructor(address admin, ILimitedMinterBridge _limitedMinter) {
        if (admin == address(0) || address(_limitedMinter) == address(0)) {
            revert ZeroAddress();
        }

        limitedMinter = _limitedMinter;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_OPERATOR_ROLE, admin);
    }

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    /// @notice For inbound fulfillments - checks if token is registered in LimitedMinterBridge
    /// @dev This is the single source of truth for mintable tokens on this chain
    modifier onlyMintableToken(address token) {
        (, bool exists) = limitedMinter.tokenConfigs(token);
        if (!exists) revert TokenNotRegisteredInMinter();
        _;
    }

    /// @notice For outbound deposits - checks if route is enabled
    modifier onlyValidRoute(address token, uint256 destChainId) {
        if (!bridgeRoutes[token][destChainId]) {
            revert InvalidRoute();
        }
        _;
    }

    // -----------------------------------------------------------------------
    // Admin functions
    // -----------------------------------------------------------------------

    /**
     * @notice Enables/disables outbound bridge routes (deposits from this chain to destination chains)
     * @dev For INBOUND fulfillments, the token must be registered in LimitedMinterBridge directly.
     *      This function only controls OUTBOUND deposits - which tokens can be burned and bridged out.
     * @param token Token address
     * @param destChainIds Array of destination chain IDs to enable/disable
     * @param enabled Whether to enable or disable these routes
     */
    function setBridgeRoutes(
        address token,
        uint256[] calldata destChainIds,
        bool enabled
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) revert ZeroAddress();

        for (uint256 i = 0; i < destChainIds.length; ) {
            if (destChainIds[i] == block.chainid) revert InvalidSourceChain();
            bridgeRoutes[token][destChainIds[i]] = enabled;
            unchecked { ++i; }
        }

        emit BridgeRoutesUpdated(token, destChainIds, enabled);
    }

    /**
     * @notice Updates the LimitedMinterBridge contract reference
     * @dev Admin must ensure this contract has MINTER_ROLE on the new LimitedMinterBridge.
     */
    function updateLimitedMinter(ILimitedMinterBridge newMinter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(newMinter) == address(0)) revert ZeroAddress();

        address old = address(limitedMinter);
        limitedMinter = newMinter;

        emit LimitedMinterUpdated(old, address(newMinter));
    }

    /**
     * @notice Pauses all bridge operations (deposits and mints)
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses all bridge operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Rescues tokens accidentally sent to this contract
     * @dev Only callable by admin. Use this to recover tokens sent directly to the contract
     *      instead of through depositForBridge.
     * @param token Address of the token to rescue
     * @param to Address to send the rescued tokens to
     * @param amount Amount of tokens to rescue
     */
    function rescueTokens(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert AmountZero();

        IERC20(token).transfer(to, amount);
        emit TokensRescued(token, to, amount);
    }

    // -----------------------------------------------------------------------
    // User-facing: Deposit (burn) on source chain
    // -----------------------------------------------------------------------

    /**
     * @notice User burns tokens on this chain to initiate a cross-chain bridge
     * @dev
     *  - User must have approved this contract for at least `amount`.
     *  - This contract calls `burnFrom(msg.sender, amount)` on the token.
     *  - Emits `BridgeDepositInitiated` that off-chain infra uses to mint on destination chain.
     *
     * @param token Address of the token to bridge
     * @param amount Amount to bridge (burn)
     * @param destChainId Destination chain ID
     * @param destRecipient Recipient address on the destination chain
     * @param clientDepositId Optional client-provided ID for correlation (e.g. from frontend)
     * @return depositId Sequential ID of this deposit on this chain
     */
    function depositForBridge(
        address token,
        uint256 amount,
        uint256 destChainId,
        address destRecipient,
        bytes32 clientDepositId
    )
        external
        nonReentrant
        whenNotPaused
        onlyValidRoute(token, destChainId)
        returns (uint256 depositId)
    {
        if (amount == 0) revert AmountZero();
        if (destRecipient == address(0)) revert InvalidRecipient();

        // Burn tokens from the user using allowance
        ILatamStableBurnable(token).burnFrom(msg.sender, amount);

        // Track total burned for conservation auditing
        totalBurnedTo[token][destChainId] += amount;

        depositId = nextDepositId++;
        emit BridgeDepositInitiated(
            depositId,
            token,
            msg.sender,
            amount,
            destChainId,
            destRecipient,
            clientDepositId
        );
    }

    // -----------------------------------------------------------------------
    // Operator-facing: Mint on destination chain using LimitedMinterBridge
    // -----------------------------------------------------------------------

    /**
     * @notice Fulfills a bridge by minting tokens on this chain to the recipient.
     * @dev
     *  - Callable only by BRIDGE_OPERATOR_ROLE (off-chain bridge service).
     *  - This contract must have MINTER_ROLE on LimitedMinterBridge so that `mintTo` succeeds.
     *  - LimitedMinterBridge enforces the daily mint limit per token.
     *  - Idempotency: composite key of (sourceChainId, sourceTxHash, sourceDepositId)
     *    ensures uniqueness across chains and within multi-deposit transactions.
     *
     *  @param token Address of the token to mint
     *  @param to Recipient on this chain
     *  @param amount Amount to mint
     *  @param sourceChainId Chain ID of the source chain where the deposit occurred
     *  @param sourceTxHash Transaction hash of the source chain deposit (for auditability)
     *  @param sourceDepositId The depositId from BridgeDepositInitiated event on source chain
     */
    function fulfillBridgeMint(
        address token,
        address to,
        uint256 amount,
        uint256 sourceChainId,
        bytes32 sourceTxHash,
        uint256 sourceDepositId
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(BRIDGE_OPERATOR_ROLE)
        onlyMintableToken(token)
    {
        // Prevent same-chain fulfillment
        if (sourceChainId == block.chainid) revert InvalidSourceChain();

        // Composite key for idempotency: chainId + txHash + depositId
        bytes32 fulfillmentKey = keccak256(
            abi.encodePacked(sourceChainId, sourceTxHash, sourceDepositId)
        );

        if (bridgeFulfilled[fulfillmentKey]) revert BridgeAlreadyFulfilled();
        if (amount == 0) revert AmountZero();
        if (to == address(0)) revert InvalidRecipient();

        bridgeFulfilled[fulfillmentKey] = true;

        // Mint via LimitedMinterBridge (enforces per-day limits)
        limitedMinter.mintTo(token, to, amount);

        // Track total minted for conservation auditing
        totalMintedFrom[token][sourceChainId] += amount;

        emit BridgeMintFulfilled(
            token,
            to,
            amount,
            sourceChainId,
            sourceTxHash,
            sourceDepositId
        );
    }

    // -----------------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------------

    /**
     * @notice Returns current minting capacity remaining today for a token on this chain
     * @dev Convenience view that proxies LimitedMinterBridge.
     */
    function remainingMintCapacity(address token)
        external
        view
        returns (uint256 remaining, uint256 dailyMaxMint, uint256 mintedToday_)
    {
        (dailyMaxMint, ) = limitedMinter.tokenConfigs(token);
        mintedToday_ = limitedMinter.mintedToday(token);
        if (dailyMaxMint > mintedToday_) {
            remaining = dailyMaxMint - mintedToday_;
        } else {
            remaining = 0;
        }
    }

    /**
     * @notice Returns conservation stats for cross-chain auditing
     * @dev Compare burnedTo on source chain with mintedFrom on destination chain
     * @param token Token address
     * @param chainId Chain ID to query stats for
     * @return burnedTo Total tokens burned to this chainId (outbound)
     * @return mintedFrom Total tokens minted from this chainId (inbound)
     */
    function getBridgeStats(address token, uint256 chainId)
        external
        view
        returns (uint256 burnedTo, uint256 mintedFrom)
    {
        burnedTo = totalBurnedTo[token][chainId];
        mintedFrom = totalMintedFrom[token][chainId];
    }
}

