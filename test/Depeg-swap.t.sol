// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AssetFactory} from "../src/contracts/core/assets/AssetFactory.sol";
import {Asset} from "../src/contracts/core/assets/Asset.sol";
import {IUniswapV2Factory} from "../src/contracts/interfaces/uniswap-v2/factory.sol";
import {RouterState} from "../src/contracts/core/flash-swaps/FlashSwapRouter.sol";
import {IUniswapV2Router02} from "../src/contracts/interfaces/uniswap-v2/RouterV2.sol";
import {CorkConfig} from "../src/contracts/core/CorkConfig.sol";
import {ModuleCore} from "../src/contracts/core/ModuleCore.sol";
import {Id} from "../src/contracts/libraries/Pair.sol";
import {DummyWETH} from "../src/contracts/dummy/DummyWETH.sol";
import {DummyERCWithMetadata} from "../src/contracts/dummy/DummyERC20WithMetadata.sol";

contract DepegSwapTest is Test {
    uint256 mainnetFork;

    AssetFactory assetFactory;
    CorkConfig corkConfig;
    ModuleCore moduleCore;
    RouterState flashswapRouter;
    IUniswapV2Factory univ2Factory;
    IUniswapV2Router02 uniswapRouter;

    DummyWETH ra;
    DummyERCWithMetadata pa;

    Asset depeg_swap;
    Asset cover_token;
    Asset lv_token;

    address OWNER = makeAddr("dsOwner");
    address USER = makeAddr("user");

    uint ASSET_INITIAL_EXR = 2e18; // TODO understand what that means

    uint256 constant PSM_BASE_REDEMPTION_FEE = 5e18;
    Id vaultId;

    modifier isEthMainnetFork() {
        vm.selectFork(mainnetFork);
        _;
    }

    modifier userHasRafunds() {
        vm.startPrank(USER);
        vm.deal(USER, 10 ether);
        ra.deposit{value: 10 ether}();
        ra.approve(address(moduleCore), 10 ether);
        vm.stopPrank();
        _;
    }

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

        // TODO create 2 new erc20 tokens as ra and pa
        // Create two new ERC20 tokens as RA and PA
        ra = new DummyWETH();
        pa = new DummyERCWithMetadata("Pegged Asset", "PA");

        // Replace the makeAddr calls with the actual token addresses
        corkConfig.initializeModuleCore(address(pa), address(ra), 2e18, 1);

        vaultId = moduleCore.getId(address(pa), address(ra));

        corkConfig.issueNewDs(
            vaultId,
            block.timestamp + 100,
            ASSET_INITIAL_EXR,
            2e18
        );

        (address[] memory ct, address[] memory ds) = assetFactory
            .getDeployedSwapAssets(
                address(ra),
                address(pa),
                uint8(0),
                uint8(1)
            );

        (, address[] memory lv) = assetFactory.getDeployedAssets(
            uint8(0),
            uint8(1)
        );
        cover_token = Asset(ct[0]);
        depeg_swap = Asset(ds[0]);
        lv_token = Asset(lv[0]);

        vm.stopPrank();
        // Create handler

        // Set up your invariant test targets
        //targetContract(address(handler));
    }

    function test_forkworking() public isEthMainnetFork {
        assert(vm.activeFork() == mainnetFork);
    }

    function test_depositPSM() public isEthMainnetFork userHasRafunds {
        uint RaDepositAmmount = 1e18;
        uint expected_ctdsReturn = (RaDepositAmmount * 1e18) /
            ASSET_INITIAL_EXR;
        // deposit Ra to psm and get back ct - ds
        vm.startPrank(USER);

        // Approve ModuleCore to spend DWETH
        ra.approve(address(moduleCore), RaDepositAmmount);
        (uint received, uint exr) = moduleCore.depositPsm(
            vaultId,
            RaDepositAmmount
        );

        (uint received2, uint exr2) = moduleCore.depositPsm(
            vaultId,
            RaDepositAmmount
        );

        console.log(exr2, exr); // proves exr on redeem does not change

        assert(cover_token.balanceOf(USER) == depeg_swap.balanceOf(USER));
        assert(expected_ctdsReturn == received);
        vm.stopPrank();
    }

    function test_EarlyredeemDsCtForRa() public {}

    function testDepositLv() public isEthMainnetFork userHasRafunds {
        vm.startPrank(USER);

        uint amountToDeposit = 1e18; // deposit WETH
        uint ammountReceived;
        uint expectedLv = (amountToDeposit * 1e18) / ASSET_INITIAL_EXR;

        moduleCore.depositLv(vaultId, amountToDeposit);
        ammountReceived = lv_token.balanceOf(USER); // @audit 1 - 1 excangeRate? does it make sense
        // TODO see how excangeRate works
        assert(ammountReceived == amountToDeposit);
        moduleCore.depositLv(vaultId, amountToDeposit);
        console.log(depeg_swap.balanceOf(address(flashswapRouter)));

        // check same ratio applies for second deposit where value is obtained trhoug amm
        assert(amountToDeposit * 2 == lv_token.balanceOf(USER));
        vm.stopPrank();
    }

    function test_redeemRaWithCtDs() public isEthMainnetFork userHasRafunds {
        vm.startPrank(USER);
        uint ammountToDeposit = 1e18;
        (uint received, ) = moduleCore.depositPsm(vaultId, ammountToDeposit);
        depeg_swap.approve(address(moduleCore), received);
        cover_token.approve(address(moduleCore), received);
        (uint receivedRa, uint rates) = moduleCore.redeemRaWithCtDs(
            vaultId,
            received
        );

        assert(receivedRa == ammountToDeposit);
        vm.stopPrank();
    }

    function test_swapFuncs() public isEthMainnetFork userHasRafunds {
        vm.startPrank(USER);
        uint amount = 2e18;
        moduleCore.depositLv(vaultId, amount);
        moduleCore.depositLv(vaultId, amount);
        Id reserveId = moduleCore.getId(address(pa), address(ra));
        uint dsId = moduleCore.lastDsId(reserveId);
        ra.approve(address(flashswapRouter), amount);
        // @audit here with 2e15 and low numbers occurs a over - underflow err
        moduleCore.depositPsm(vaultId, 1e18);
        depeg_swap.approve(address(flashswapRouter), 1e15);
        flashswapRouter.swapRaforDs(reserveId, dsId, 1e15, 0);
        flashswapRouter.swapDsforRa(reserveId, dsId, 1e15, 0);
    }
}
