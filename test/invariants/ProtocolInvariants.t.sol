pragma solidity ^0.8.24;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {DepegSwapHandler} from "../handler/DepegSwapHandler.t.sol";
import {AssetFactory, Asset} from "../../src/contracts/core/assets/AssetFactory.sol";
import {IUniswapV2Factory} from "../../src/contracts/interfaces/uniswap-v2/factory.sol";
import {RouterState} from "../../src/contracts/core/flash-swaps/FlashSwapRouter.sol";
import {IUniswapV2Router02} from "../../src/contracts/interfaces/uniswap-v2/RouterV2.sol";
import {CorkConfig} from "../../src/contracts/core/CorkConfig.sol";
import {ModuleCore} from "../../src/contracts/core/ModuleCore.sol";
import {DummyWETH} from "../../src/contracts/dummy/DummyWETH.sol";
import {Id} from "../../src/contracts/libraries/Pair.sol";
import {DummyERCWithMetadata} from "../../src/contracts/dummy/DummyERC20WithMetadata.sol";

contract ProtocolInvariants is StdInvariant, Test {
    uint256 mainnetFork;
    //ProtocolHandler public handler;
    AssetFactory assetFactory;
    CorkConfig corkConfig;
    ModuleCore moduleCore;
    RouterState flashswapRouter;
    IUniswapV2Factory univ2Factory;
    IUniswapV2Router02 uniswapRouter;

    DummyWETH ra;
    DummyERCWithMetadata pa;

    Id vaultId;

    Asset ds;
    Asset ct;

    DepegSwapHandler handler;

    address OWNER = makeAddr("dsOwner");
    address USER = makeAddr("user");

    uint256 constant PSM_BASE_REDEMPTION_FEE = 5e18;

    function setUp() public {
        // Fork mainnet
        mainnetFork = vm.createFork(vm.envString("fork_url"));
        vm.selectFork(mainnetFork);

        // Set up mainnet contract addresses
        univ2Factory = IUniswapV2Factory(
            0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
        );
        uniswapRouter = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        vm.startPrank(OWNER);
        corkConfig = new CorkConfig();
        // Deploy your protocol contracts
        assetFactory = new AssetFactory(); // TODO deploy as upgradeable
        flashswapRouter = new RouterState(); // TODO deploy as upgradeable
        moduleCore = new ModuleCore(
            address(assetFactory),
            address(univ2Factory),
            address(flashswapRouter),
            address(uniswapRouter),
            address(corkConfig),
            PSM_BASE_REDEMPTION_FEE
        );
        // set module core in config + initialize it
        corkConfig.setModuleCore(address(moduleCore));

        flashswapRouter.initialize(address(moduleCore), address(uniswapRouter));
        assetFactory.initialize(address(moduleCore));

        ra = new DummyWETH();
        pa = new DummyERCWithMetadata("Pegged Asset", "PA");

        corkConfig.initializeModuleCore(address(pa), address(ra), 2e18, 1);

        vaultId = moduleCore.getId(address(pa), address(ra));

        corkConfig.issueNewDs(vaultId, block.timestamp + 20 days, 1e18, 2e18);

        (address[] memory _ct, address[] memory _ds) = assetFactory
            .getDeployedSwapAssets(
                address(ra),
                address(pa),
                uint8(0),
                uint8(1)
            );

        ct = Asset(_ct[0]);
        ds = Asset(_ds[0]);

        vm.stopPrank();

        handler = new DepegSwapHandler(
            moduleCore,
            ra,
            address(ct),
            address(ds),
            address(pa),
            vaultId
        );

        // target handler selectors
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.depositPsm.selector;
        selectors[1] = handler.withDrawRawithCTDS.selector;
        selectors[2] = handler.redeemRawithDsPa.selector;

        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
        targetContract(address(handler));

        // Set up your invariant test targets
        //targetContract(address(handler));
    }

    function invariant_totalSupply() public {
        vm.selectFork(mainnetFork);
        assertEq(
            handler.totalAmountDepositted(),
            ra.balanceOf(address(moduleCore))
        );
    }
}
