// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract StabiXVault is Initializable, UUPSUpgradeable, OwnableUpgradeable {

    IERC20 public usdc;

    enum VaultState {
        NORMAL,
        RESTRICTED,
        FREEZE
    }

    struct RootData {
        bytes32 root;
        uint256 createdAt;
        uint256 expiresAt;
        uint256 liabilities;
        bool active;
    }

    struct PendingConfig {
        uint256 maxDailyRebalances;
        uint256 rebalancePercent;
        uint256 claimWindow;
        uint256 executeAfter;
        bool pending;
    }

    mapping(uint256 => RootData) public roots;
    mapping(bytes32 => bool) public claimed;
    mapping(bytes32 => string) public proofSTR;
    mapping(address => bool) public multisig;

    uint256 public multisigCount;
    uint256 public currentRootId;
    uint256 public reservedFunds;
    uint256 public dailyRebalanceUsed;
    uint256 public dailyRebalanceCount;
    uint256 public lastRebalanceDay;

    uint256 public maxDailyRebalances;
    uint256 public rebalancePercent;
    uint256 public claimWindow;
    uint256 public freezeExtension;

    bool public unfreezeQueued;
    uint256 public unfreezeTime;

    VaultState public vaultState;
    PendingConfig public pendingConfig;

    event Deposit(address indexed from, uint256 amount);
    event Withdraw(address indexed user, uint256 amount, uint256 rootId);
    event RootUploaded(
        uint256 indexed rootId,
        bytes32 root,
        uint256 liabilities,
        uint256 expiresAt
    );
    event Rebalance(address indexed to, uint256 amount);
    event RestrictedMode();
    event FreezeMode();
    event UnfreezeQueued(uint256 executeAt);
    event UnfreezeExecuted();
    event ConfigQueued(uint256 executeAfter);
    event ConfigUpdated();
    event MultisigAdded(address indexed signer);
    event MultisigRemoved(address indexed signer);

    modifier onlyMultisig() {
        require(multisig[msg.sender], "NOT_MULTISIG");
        _;
    }

    function initialize(address _usdc) public initializer {
        __Ownable_init(msg.sender);

        usdc = IERC20(_usdc);

        vaultState = VaultState.NORMAL;
        multisig[msg.sender] = true;
        multisigCount = 1;

        maxDailyRebalances = 2;
        rebalancePercent = 5;
        claimWindow = 24 hours;
        freezeExtension = 72 hours;

        emit MultisigAdded(msg.sender);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function deposit(uint256 amount) external {
        require(amount > 0, "INVALID_AMOUNT");

        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "TRANSFER_FAILED"
        );

        emit Deposit(msg.sender, amount);
    }

    function uploadRoot(
        bytes32 root,
        address[] calldata users,
        uint256[] calldata amounts,
        string[] calldata strIds,
        uint256 liabilities
    ) external onlyMultisig {
        require(vaultState != VaultState.FREEZE, "VAULT_FROZEN");

        require(
            users.length == amounts.length &&
            amounts.length == strIds.length,
            "LENGTH_MISMATCH"
        );

        if (currentRootId > 0) {
            RootData storage oldRoot = roots[currentRootId];

            if (oldRoot.active && block.timestamp > oldRoot.expiresAt) {
                reservedFunds -= oldRoot.liabilities;
                oldRoot.active = false;
            }
        }

        currentRootId++;

        roots[currentRootId] = RootData({
            root: root,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + claimWindow,
            liabilities: liabilities,
            active: true
        });

        for (uint256 i = 0; i < users.length; i++) {
            bytes32 leaf = keccak256(
                abi.encodePacked(users[i], amounts[i], currentRootId)
            );

            proofSTR[leaf] = strIds[i];
        }

        reservedFunds += liabilities;

        emit RootUploaded(
            currentRootId,
            root,
            liabilities,
            block.timestamp + claimWindow
        );
    }

    function withdraw(
        uint256 rootId,
        uint256 amount,
        bytes32[] calldata proof
    ) external {
        RootData storage r = roots[rootId];

        require(r.active, "ROOT_INACTIVE");
        require(block.timestamp <= r.expiresAt, "ROOT_EXPIRED");

        bytes32 leaf = keccak256(
            abi.encodePacked(msg.sender, amount, rootId)
        );

        require(!claimed[leaf], "ALREADY_CLAIMED");
        require(verify(proof, r.root, leaf), "INVALID_PROOF");

        claimed[leaf] = true;

        reservedFunds -= amount;
        r.liabilities -= amount;

        if (r.liabilities == 0) {
            r.active = false;
        }

        require(
            usdc.transfer(msg.sender, amount),
            "TRANSFER_FAILED"
        );

        emit Withdraw(msg.sender, amount, rootId);
    }

    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) public pure returns (bool) {
        bytes32 hash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 p = proof[i];

            if (hash <= p) {
                hash = keccak256(abi.encodePacked(hash, p));
            } else {
                hash = keccak256(abi.encodePacked(p, hash));
            }
        }

        return hash == root;
    }

    function vaultBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}
