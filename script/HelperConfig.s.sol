// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import {MockV3Aggregator} from "../test/mock/MockV3Aggregator.sol";
import {Script, console2} from "forge-std/Script.sol";

abstract contract CodeConstants {
    // uint8 public constant DECIMALS = 8;
    // int256 public constant INITIAL_PRICE = 2000e8;
    uint256 public constant CREATION_FEE = 200e18; // in $
    uint256 public constant SUCCESSFUL_END_FEE = 5e16; // percentage, e.g. 5e16 = 5%
    // Whitehatdao.eth address for fee collector
    address public constant WHITE_HAT_DAO = 0xB5A790568471c23dE46533F1706a238B04D59F25;

    /*//////////////////////////////////////////////////////////////
                               CHAIN IDS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;
    // uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        uint256 successfulEndFee;
        address feeCollector;
        uint256 creationFee;
        uint256 a;
        uint256 swapFee;
        uint256 minInitialEthAmount;
        address priceFeed;
        address uniFactory;
        address nonfungiblePositionManager;
        address weth;
        uint256 deployerKey;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Local network state variables
    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigs[BASE_SEPOLIA_CHAIN_ID] = getBaseSepoliaConfig();
        // Note: We skip doing the local config
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public view returns (NetworkConfig memory) {
        if (networkConfigs[chainId].priceFeed != address(0)) {
            return networkConfigs[chainId];
        // } else if (chainId == LOCAL_CHAIN_ID) {
        //     return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                CONFIGS
    //////////////////////////////////////////////////////////////*/
    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            successfulEndFee: SUCCESSFUL_END_FEE,
            feeCollector: address(uint160(vm.envUint("FEE_COLLECTOR"))), // address of the private key
            creationFee: CREATION_FEE,
            a: 0.001e18,
            swapFee: 0.005e18,
            minInitialEthAmount: 5e18,
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            uniFactory: 0x0227628f3F023bb0B980b67D528571c95c6DaC1c,
            nonfungiblePositionManager: 0x1238536071E1c677A632429e3655c799b22cDA52,
            weth: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getBaseSepoliaConfig() public view returns (NetworkConfig memory) {
        // NOT CORRECT JUST PLACEHOLDER
        return NetworkConfig({
            successfulEndFee: SUCCESSFUL_END_FEE,
            feeCollector: address(uint160(vm.envUint("FEE_COLLECTOR"))),
            creationFee: CREATION_FEE,
            a: 0.001e18,
            swapFee: 0.005e18,
            minInitialEthAmount: 5e18,
            priceFeed: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1,
            uniFactory: 0x0227628f3F023bb0B980b67D528571c95c6DaC1c,
            nonfungiblePositionManager: 0x1238536071E1c677A632429e3655c799b22cDA52,
            weth: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    /*//////////////////////////////////////////////////////////////
                              LOCAL CONFIG
    //////////////////////////////////////////////////////////////*/
    // function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
    //     // Check to see if we set an active network config
    //     if (localNetworkConfig.priceFeed != address(0)) {
    //         return localNetworkConfig;
    //     }

    //     console2.log(unicode"⚠️ You have deployed a mock contract!");
    //     console2.log("Make sure this was intentional");
    //     vm.startBroadcast();
    //     MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    //     vm.stopBroadcast();

    //     localNetworkConfig = NetworkConfig({priceFeed: address(mockPriceFeed)});
    //     return localNetworkConfig;
    // }
}