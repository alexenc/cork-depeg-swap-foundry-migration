// SPDX-License-Identifier: UNLICENSED

import "forge-std/Test.sol";

contract TimeWarper is Test {
    function warp(uint256 amount) external {
        vm.warp(bound(amount, block.timestamp + 1, block.timestamp + 1 days));
    }
}
