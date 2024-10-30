pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ModuleCore} from "../../src/contracts/core/ModuleCore.sol";
import {Id} from "../../src/contracts/libraries/Pair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RouterState} from "../../src/contracts/core/flash-swaps/FlashSwapRouter.sol";
import {DummyWETH} from "../../src/contracts/dummy/DummyWETH.sol";
import {DummyERCWithMetadata} from "../../src/contracts/dummy/DummyERC20WithMetadata.sol";

contract DepegSwapHandler is Test {
    uint userRaDeposit = 0;
    ModuleCore moduleCoreContract;
    Id private initialVaultId;

    DummyWETH private ra;
    IERC20 private pa;
    IERC20 private ct;
    IERC20 private ds;

    uint public totalAmountDepositted = 0;

    address USER1 = makeAddr("1");
    address USER2 = makeAddr("2");

    constructor(
        ModuleCore _moduleCore,
        DummyWETH _ra,
        address _ct,
        address _ds,
        address _pa,
        Id _initialVaultId
    ) {
        moduleCoreContract = _moduleCore;
        ra = DummyWETH(_ra);
        ct = IERC20(_ct);
        ds = IERC20(_ds);
        pa = IERC20(_pa);

        initialVaultId = _initialVaultId;
    }

    function depositPsm(uint256 amount) public {
        amount = bound(amount, 1, 10e18);
        address selectedAddress = amount % 2 == 0 ? USER1 : USER2;
        vm.deal(selectedAddress, amount);

        vm.startPrank(selectedAddress);
        ra.deposit{value: amount}();
        ra.approve(address(moduleCoreContract), amount);
        moduleCoreContract.depositPsm(initialVaultId, amount);
        vm.stopPrank();
        totalAmountDepositted += amount;
    }

    function redeemRawithDsPa(uint256 amount) public {
        amount = bound(amount, 1, 10e18);
        address selectedAddress = amount % 2 == 0 ? USER1 : USER2;

        uint256 userDsBalance = ds.balanceOf(selectedAddress);

        if (userDsBalance <= 0) return;
        if (userDsBalance < amount) amount = userDsBalance;

        vm.startPrank(selectedAddress);
        DummyERCWithMetadata(address(pa)).mint(selectedAddress, amount);
        pa.approve(address(moduleCoreContract), amount);
        ds.approve(address(moduleCoreContract), amount);

        Id reserveId = moduleCoreContract.getId(address(pa), address(ra));
        uint dsId = moduleCoreContract.lastDsId(reserveId);

        moduleCoreContract.redeemRaWithDs(initialVaultId, dsId, amount);

        vm.stopPrank();
    }

    function withDrawRawithCTDS(uint256 amount) public {
        amount = bound(amount, 1, 1e18);
        address selectedAddress = amount % 2 == 0 ? USER1 : USER2;

        uint userCTDSBalance = ct.balanceOf(selectedAddress);

        if (userCTDSBalance <= 0) return; // user has no deposits
        if (amount > userCTDSBalance) amount = userCTDSBalance;
        vm.startPrank(selectedAddress);
        ds.approve(address(moduleCoreContract), amount);
        ct.approve(address(moduleCoreContract), amount);
        moduleCoreContract.redeemRaWithCtDs(initialVaultId, amount);
        vm.stopPrank();
        totalAmountDepositted -= amount;
    }
}
