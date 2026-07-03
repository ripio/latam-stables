// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITIP20} from "./interfaces/ITIP20.sol";

interface ITip20LimitedMinterBridge {
    function mintTo(address token, address to, uint256 mintAmount) external;
    function mintTo(address token, address to, uint256 mintAmount, bytes32 memo) external;
    function mintToWithMemo(address token, address to, uint256 mintAmount, bytes32 memo) external;
    function mintedToday(address token) external view returns (uint256);
    function tokenConfigs(address token) external view returns (uint256 dailyMaxMint, bool exists);
}

/**
 * @title Tip20BridgeDeposit
 * @notice Tempo-native bridge deposit and fulfillment contract for TIP-20 tokens.
 * @dev Source-chain deposits pull approved TIP-20 tokens into this contract,
 *      optionally forward fees, then burn or burnWithMemo from this contract balance.
 *      Destination-chain fulfillment mints through Tip20LimitedMinterBridge.
 */
contract Tip20BridgeDeposit is AccessControlEnumerable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant BRIDGE_OPERATOR_ROLE = keccak256("BRIDGE_OPERATOR_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    struct RouteConfig {
        bool enabled;
        uint256 fixedFee;
    }

    ITip20LimitedMinterBridge public limitedMinter;
    address public feeCollector;

    mapping(address => mapping(uint256 => RouteConfig)) public routeConfigs;
    uint256 public nextDepositId = 1;

    mapping(bytes32 => bool) public bridgeFulfilled;
    mapping(address => mapping(uint256 => uint256)) public totalBurnedTo;
    mapping(address => mapping(uint256 => uint256)) public totalFeesCollected;
    mapping(address => mapping(uint256 => uint256)) public totalMintedFrom;

    error ZeroAddress();
    error AmountZero();
    error InvalidRecipient();
    error BridgeAlreadyFulfilled();
    error TokenNotRegisteredInMinter();
    error InvalidSourceChain();
    error InvalidRoute();
    error AmountTooLowForFee();
    error UnexpectedTokenDelivery();

    event BridgeDepositInitiated(
        uint256 indexed depositId,
        address indexed token,
        address indexed from,
        uint256 amount,
        uint256 fee,
        uint256 destChainId,
        address destRecipient,
        bytes32 clientDepositId
    );

    event BridgeMintFulfilled(
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 sourceChainId,
        bytes32 sourceTxHash,
        uint256 indexed sourceDepositId,
        bytes32 memo
    );

    event BridgeRoutesUpdated(address indexed token, uint256[] destChainIds, bool enabled, uint256 fixedFee);
    event LimitedMinterUpdated(address indexed oldMinter, address indexed newMinter);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event FeeCollectorUpdated(address indexed oldFeeCollector, address indexed newFeeCollector);
    event RouteFeeUpdated(address indexed token, uint256 indexed destChainId, uint256 oldFee, uint256 newFee);

    constructor(address admin, ITip20LimitedMinterBridge _limitedMinter, address _feeCollector) {
        if (admin == address(0) || address(_limitedMinter) == address(0)) {
            revert ZeroAddress();
        }

        limitedMinter = _limitedMinter;
        feeCollector = _feeCollector;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BRIDGE_OPERATOR_ROLE, admin);
        _grantRole(FEE_MANAGER_ROLE, admin);
    }

    modifier onlyMintableToken(address token) {
        (, bool exists) = limitedMinter.tokenConfigs(token);
        if (!exists) revert TokenNotRegisteredInMinter();
        _;
    }

    function setBridgeRoutes(address token, uint256[] calldata destChainIds, bool enabled, uint256 fixedFee)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (token == address(0)) revert ZeroAddress();

        for (uint256 i = 0; i < destChainIds.length;) {
            if (destChainIds[i] == block.chainid) revert InvalidSourceChain();
            routeConfigs[token][destChainIds[i]] = RouteConfig({enabled: enabled, fixedFee: fixedFee});
            unchecked {
                ++i;
            }
        }

        emit BridgeRoutesUpdated(token, destChainIds, enabled, fixedFee);
    }

    function updateLimitedMinter(ITip20LimitedMinterBridge newMinter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(newMinter) == address(0)) revert ZeroAddress();

        address old = address(limitedMinter);
        limitedMinter = newMinter;

        emit LimitedMinterUpdated(old, address(newMinter));
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function rescueTokens(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert AmountZero();

        _checkedTransfer(IERC20(token), to, amount);
        emit TokensRescued(token, to, amount);
    }

    function setFeeCollector(address newFeeCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldFeeCollector = feeCollector;
        feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(oldFeeCollector, newFeeCollector);
    }

    function updateRouteFee(address token, uint256 destChainId, uint256 newFixedFee)
        external
        onlyRole(FEE_MANAGER_ROLE)
    {
        RouteConfig storage route = routeConfigs[token][destChainId];
        if (!route.enabled) revert InvalidRoute();

        uint256 oldFee = route.fixedFee;
        route.fixedFee = newFixedFee;

        emit RouteFeeUpdated(token, destChainId, oldFee, newFixedFee);
    }

    function depositForBridge(
        address token,
        uint256 amount,
        uint256 destChainId,
        address destRecipient
    ) external nonReentrant whenNotPaused returns (uint256 depositId) {
        depositId = _depositForBridge(token, amount, destChainId, destRecipient, bytes32(0), false);
    }

    function depositForBridgeWithMemo(
        address token,
        uint256 amount,
        uint256 destChainId,
        address destRecipient,
        bytes32 clientDepositId
    ) external nonReentrant whenNotPaused returns (uint256 depositId) {
        depositId = _depositForBridge(token, amount, destChainId, destRecipient, clientDepositId, true);
    }

    function depositForBridge(
        address token,
        uint256 amount,
        uint256 destChainId,
        address destRecipient,
        bytes32 clientDepositId
    ) external nonReentrant whenNotPaused returns (uint256 depositId) {
        depositId = _depositForBridge(token, amount, destChainId, destRecipient, clientDepositId, true);
    }

    function fulfillBridgeMint(
        address token,
        address to,
        uint256 amount,
        uint256 sourceChainId,
        bytes32 sourceTxHash,
        uint256 sourceDepositId
    ) external nonReentrant whenNotPaused onlyRole(BRIDGE_OPERATOR_ROLE) onlyMintableToken(token) {
        _fulfillBridgeMint(token, to, amount, sourceChainId, sourceTxHash, sourceDepositId, bytes32(0), false);
    }

    function fulfillBridgeMintWithMemo(
        address token,
        address to,
        uint256 amount,
        uint256 sourceChainId,
        bytes32 sourceTxHash,
        uint256 sourceDepositId,
        bytes32 memo
    ) external nonReentrant whenNotPaused onlyRole(BRIDGE_OPERATOR_ROLE) onlyMintableToken(token) {
        _fulfillBridgeMint(token, to, amount, sourceChainId, sourceTxHash, sourceDepositId, memo, true);
    }

    function fulfillBridgeMint(
        address token,
        address to,
        uint256 amount,
        uint256 sourceChainId,
        bytes32 sourceTxHash,
        uint256 sourceDepositId,
        bytes32 memo
    ) external nonReentrant whenNotPaused onlyRole(BRIDGE_OPERATOR_ROLE) onlyMintableToken(token) {
        _fulfillBridgeMint(token, to, amount, sourceChainId, sourceTxHash, sourceDepositId, memo, true);
    }

    function _depositForBridge(
        address token,
        uint256 amount,
        uint256 destChainId,
        address destRecipient,
        bytes32 clientDepositId,
        bool useMemo
    ) internal returns (uint256 depositId) {
        if (amount == 0) revert AmountZero();
        if (destRecipient == address(0)) revert InvalidRecipient();
        if (destChainId == block.chainid) revert InvalidSourceChain();

        RouteConfig memory route = routeConfigs[token][destChainId];
        if (!route.enabled) revert InvalidRoute();
        if (route.fixedFee >= amount) revert AmountTooLowForFee();

        uint256 amountToBurn = amount - route.fixedFee;
        IERC20 tokenContract = IERC20(token);

        _checkedTransferFrom(tokenContract, msg.sender, address(this), amount);

        if (route.fixedFee > 0) {
            if (feeCollector == address(0)) revert ZeroAddress();
            _checkedTransfer(tokenContract, feeCollector, route.fixedFee);
            totalFeesCollected[token][destChainId] += route.fixedFee;
        }

        if (useMemo) {
            _checkedBurnWithMemo(token, amountToBurn, clientDepositId);
        } else {
            _checkedBurn(token, amountToBurn);
        }

        totalBurnedTo[token][destChainId] += amountToBurn;

        depositId = nextDepositId++;
        emit BridgeDepositInitiated(
            depositId, token, msg.sender, amountToBurn, route.fixedFee, destChainId, destRecipient, clientDepositId
        );
    }

    function _fulfillBridgeMint(
        address token,
        address to,
        uint256 amount,
        uint256 sourceChainId,
        bytes32 sourceTxHash,
        uint256 sourceDepositId,
        bytes32 memo,
        bool useMemo
    ) internal {
        if (sourceChainId == block.chainid) revert InvalidSourceChain();
        if (amount == 0) revert AmountZero();
        if (to == address(0)) revert InvalidRecipient();

        bytes32 fulfillmentKey = keccak256(abi.encodePacked(sourceChainId, sourceTxHash, sourceDepositId));
        if (bridgeFulfilled[fulfillmentKey]) revert BridgeAlreadyFulfilled();

        bridgeFulfilled[fulfillmentKey] = true;

        if (useMemo) {
            limitedMinter.mintToWithMemo(token, to, amount, memo);
        } else {
            limitedMinter.mintTo(token, to, amount);
        }
        totalMintedFrom[token][sourceChainId] += amount;

        emit BridgeMintFulfilled(token, to, amount, sourceChainId, sourceTxHash, sourceDepositId, memo);
    }

    function remainingMintCapacity(address token)
        external
        view
        returns (uint256 remaining, uint256 dailyMaxMint, uint256 mintedToday_)
    {
        (dailyMaxMint,) = limitedMinter.tokenConfigs(token);
        mintedToday_ = limitedMinter.mintedToday(token);
        if (dailyMaxMint > mintedToday_) {
            remaining = dailyMaxMint - mintedToday_;
        }
    }

    function getBridgeStats(address token, uint256 chainId)
        external
        view
        returns (uint256 burnedTo, uint256 mintedFrom)
    {
        burnedTo = totalBurnedTo[token][chainId];
        mintedFrom = totalMintedFrom[token][chainId];
    }

    function _checkedTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        uint256 balanceBefore = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        uint256 balanceAfter = token.balanceOf(to);
        if (balanceAfter < balanceBefore || balanceAfter - balanceBefore != amount) {
            revert UnexpectedTokenDelivery();
        }
    }

    function _checkedTransfer(IERC20 token, address to, uint256 amount) internal {
        uint256 balanceBefore = token.balanceOf(to);
        token.safeTransfer(to, amount);
        uint256 balanceAfter = token.balanceOf(to);
        if (balanceAfter < balanceBefore || balanceAfter - balanceBefore != amount) {
            revert UnexpectedTokenDelivery();
        }
    }

    function _checkedBurn(address token, uint256 amount) internal {
        ITIP20 tip20 = ITIP20(token);
        uint256 balanceBefore = tip20.balanceOf(address(this));
        tip20.burn(amount);
        uint256 balanceAfter = tip20.balanceOf(address(this));
        if (balanceBefore < amount || balanceBefore - balanceAfter != amount) {
            revert UnexpectedTokenDelivery();
        }
    }

    function _checkedBurnWithMemo(address token, uint256 amount, bytes32 memo) internal {
        ITIP20 tip20 = ITIP20(token);
        uint256 balanceBefore = tip20.balanceOf(address(this));
        tip20.burnWithMemo(amount, memo);
        uint256 balanceAfter = tip20.balanceOf(address(this));
        if (balanceBefore < amount || balanceBefore - balanceAfter != amount) {
            revert UnexpectedTokenDelivery();
        }
    }
}
