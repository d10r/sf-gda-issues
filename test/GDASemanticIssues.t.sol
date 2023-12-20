pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { ISuperfluid, ISuperToken, ISuperfluidPool, PoolConfig }
    from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
using SuperTokenV1Library for ISuperToken;

// convenience helper function for console logging
function toU256(int96 i96) pure returns (uint256) {
    return uint256(uint96(i96));
}

/*
 * This test contract makes the point that the currently implemented semantics of flow distribution is flawed.
 *
 * The pool state, defined by unit allocations and distribution flowrate, does not determine the effective flowrate (how much is being distirbuted to pool members).
 * Instead, the effective flowrate additionally depeonds on the past order of `distributeFlow` and `updateMemberUnits` actions.
 *
 * Definitions:
 * - targetFlowRate: the flowrate a flow sender wants to distribute via a pool, expressed by the `flowRate` argument of `distributeFlow` invocations.
 * - actualFlowRate <= targetFlowRate | the flowrate which is actually set, based on the remainder of the division by `totalUnits` at the time of the `distributeFlow` call. changes when `distributeFlow` is called.
 * - effectiveFlowRate <= actualFlowRate | the flowrate which is actually being distributed to pool members. changes when `updateMemberUnits` is called.
 * - adjustmentFlowRate = actualFlowRate - effectiveFlowRate | changes when `distributeFlow` or `updateMemberUnits` is called.
 *
 * The current implementation has 2 properties which can lead to less being distributed than the sender wanted.
 * I call this properties issues A and B.
 * A) The difference between targetFlowRate and actualFlowRate is locked in. Even if after the `distributeFlow` call, the totalUnits change such that the remainder of `targetFlowRate / totalUnits` gets smaller, this won't lead to the effectiveFlowRate increasing, because it's capped by actualFlowRate.
 * B) Changes in member units can only increase `adjustmentFlowRate`, not decrease it. The max. remainder of `actualFlowRate / totalUnits` encountered after setting an actualFlowRate is locked in and reset to the current remainder only the next time `distributeFlow` is invoked.
 *
 * How I believe it should work instead:
 * targetFlowRate = actualFlowRate | the difference should be set as adjustmentFlowRate. This solves issue A.
 * adjustmentFlowRate should be reduced if an invocation of `updateMemberUnits` leads to a smaller remainder than was before. This solves issue B.
 *
 * This way, the pool state (unit allocations and distribution flowrate) would always determine the effective flowrate.
 * Additionally, more would be distributed and less would go to the admin via adjustmentFlow.
 *
 * Drawbacks: none I'm aware of.
 *
 * This test contract demonstrates issues A and B by providing a lucky and an unlucky order of events for the same resulting pool states.
 * In the lucky variant, effectiveFlowrate = targetFlowRate / totalUnits * totalUnits (thus reduced only by the current division remainder, if any)
 * In the unlucky variant, effectiveFlowrate ends up lower than that due to the order of actions leading to a higher intermittent division remainder.
*/
contract GDASemanticIssuesTest is Test {
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer deployer;
    ISuperToken token;
    address alice = address(0x42);
    address bob = address(0x43);
    ISuperfluidPool pool;
    address admin = address(0x69);
    address sponsor = address(0x420);

    function setUp() public {
        // deploy prerequisites for SF framework
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        // deploy SF framework
        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();

        // create a SuperToken and fund the sponsors
        token = deployer.deployPureSuperToken("Token", "TOK", 20e6);
        token.transfer(sponsor, 10e6);

        pool = token.createPool(admin, PoolConfig(false, true));
    }

    // TESTS

    // Issue A: in the lucky variant, effectiveFlowRate = actualFlowRate = targetFlowRate
    function testIssueALucky() public {
        int96 targetFlowRate = 100;

        console.log("------ ACTIONS ------");
        _updateMemberUnits(alice, 9);
        _updateMemberUnits(bob, 11);
        _distributeFlow(sponsor, targetFlowRate);

        _printFlowRates(targetFlowRate);
    }

    // Issue A: in the unlucky variant, a different order of events leads to effectiveFlowRate < actualFlowRate < targetFlowRate
    function testIssueAUnlucky() public {
        int96 targetFlowRate = 100;

        console.log("------ ACTIONS ------");
        _updateMemberUnits(alice, 9);
        _distributeFlow(sponsor, targetFlowRate);
        _updateMemberUnits(bob, 11);

        _printFlowRates(targetFlowRate);
    }

    // Issue B: in the lucky variant, unit changes never increase the adjustment flow
    function testIssueBLucky() public {
        int96 targetFlowRate = 100;

        console.log("------ ACTIONS ------");
        _updateMemberUnits(alice, 10);
        _distributeFlow(sponsor, targetFlowRate);
        _updateMemberUnits(bob, 15);

        _printFlowRates(targetFlowRate);
    }

    // Issue B: in the unlucky variant, unit changes increase the adjustment flow, leading to effectiveFlowRate < actualFlowRate
    function testIssueBUnlucky() public {
        int96 targetFlowRate = 100;

        console.log("------ ACTIONS ------");
        _updateMemberUnits(alice, 10);
        _distributeFlow(sponsor, targetFlowRate);
        _updateMemberUnits(bob, 5);
        _updateMemberUnits(bob, 15);

        _printFlowRates(targetFlowRate);
    }

    // HELPERS

    function _getNameByAddress(address addr) internal view returns (string memory) {
        if (addr == address(alice)) return "alice";
        if (addr == address(bob)) return "bob";
    }

    function _updateMemberUnits(address member, uint128 units) internal {
        vm.startPrank(admin);
        pool.updateMemberUnits(member, units);
        vm.stopPrank();
        console.log("%s set to %s units", _getNameByAddress(member), units);
    }

    function _distributeFlow(address sender, int96 targetFR) internal {
        vm.startPrank(sender);
        token.distributeFlow(sender, pool, targetFR);
        vm.stopPrank();
        console.log("distributeFlow %s", toU256(targetFR));
    }

    // The target flowrate can't be queried from the GDA, or can it?
    function _printFlowRates(int96 targetFR) internal {
        int96 totalFR = pool.getTotalFlowRate();
        int96 adjustmentFR = sf.gda.getPoolAdjustmentFlowRate(address(pool));

        console.log("------ RESULT -------");
        console.log("totalUnits:         ", pool.getTotalUnits());
        console.log("targetFlowRate:     ", toU256(targetFR));
        console.log("actualFlowRate:     ", toU256(totalFR + adjustmentFR));
        console.log("effectiveFlowRate:  ", toU256(totalFR));
        console.log("adjustmentFlowRate: ", toU256(adjustmentFR));
        console.log("aliceFlowRate:      ", toU256(pool.getMemberFlowRate(alice)));
        console.log("bobFlowRate:        ", toU256(pool.getMemberFlowRate(bob)));
    }
}
