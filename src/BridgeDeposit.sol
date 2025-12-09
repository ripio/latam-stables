// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

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

    /// @notice Supported tokens for bridging on this chain
    mapping(address => bool) public supportedTokens;

    /// @notice Incremental ID for deposits initiated on this chain (local use / UI)
    uint256 public nextDepositId = 1;

    /// @notice Tracks whether a given bridge fulfillment has already been processed
    /// @dev Keyed by keccak256(sourceChainId, sourceTxHash, sourceDepositId)
    mapping(bytes32 => bool) public bridgeFulfilled;

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    error ZeroAddress();
    error TokenNotSupported();
    error AmountZero();
    error InvalidRecipient();
    error BridgeAlreadyFulfilled();
    error TokenNotRegisteredInMinter();
    error InvalidSourceChain();

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

    /// @notice Emitted when token support is updated
    event SupportedTokenUpdated(address indexed token, bool isSupported);

    /// @notice Emitted when LimitedMinterBridge reference is updated
    event LimitedMinterUpdated(address indexed oldMinter, address indexed newMinter);

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

    modifier onlySupportedToken(address token) {
        if (!supportedTokens[token]) {
            revert TokenNotSupported();
        }
        _;
    }

    // -----------------------------------------------------------------------
    // Admin functions
    // -----------------------------------------------------------------------

    /**
     * @notice Adds or removes a token from the supported list
     * @dev When enabling a token, ensure it is registered in LimitedMinterBridge
     *      so that minting on this chain is possible.
     */
    function setSupportedToken(address token, bool isSupported) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) revert ZeroAddress();

        if (isSupported) {
            // Validate that the token is configured on the LimitedMinterBridge (optional but recommended)
            (, bool exists) = limitedMinter.tokenConfigs(token);
            if (!exists) revert TokenNotRegisteredInMinter();
        }

        supportedTokens[token] = isSupported;
        emit SupportedTokenUpdated(token, isSupported);
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
        onlySupportedToken(token)
        returns (uint256 depositId)
    {
        if (amount == 0) revert AmountZero();
        if (destRecipient == address(0)) revert InvalidRecipient();
        // destChainId can be 0 in tests but should be validated off-chain for production

        // Burn tokens from the user using allowance
        ILatamStableBurnable(token).burnFrom(msg.sender, amount);

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
        onlySupportedToken(token)
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
}

