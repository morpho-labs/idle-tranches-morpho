// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/Test.sol";

import "../../contracts/strategies/morpho/MorphoAaveV2SupplyVaultStrategy.sol";
import "../../contracts/interfaces/IERC20Detailed.sol";
import "./TestIdleCDOBase.sol";

contract TestMorphoAaveV2SupplyVaultStrategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant ADAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    // Morpho-Aave Dai Stablecoin Supply Vault
    // https://github.com/morpho-dao/morpho-tokenized-vaults
    address internal constant maDAI = 0x36F8d0D0573ae92326827C4a82Fe4CE4C244cAb6;
    address internal constant morphoProxy = 0x777777c9898D384F785Ee44Acfe945efDFf5f3E0;

    function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
        _underlying = DAI;
        strategyToken = IERC20Detailed(maDAI);
        strategy = new MorphoAaveV2SupplyVaultStrategy();

        _strategy = address(strategy);

        // initialize
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        MorphoAaveV2SupplyVaultStrategy(_strategy).initialize(
            "Idle MorphoAaveV2SupplyVaultStrategy DAI",
            "IdleMorphoSupplyVaultStrategy[DAI]",
            address(strategyToken),
            _underlying,
            _owner,
            ADAI,
            address(0)
        );

        vm.label(morphoProxy, "MorphoProxy");
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        MorphoAaveV2SupplyVaultStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    }

    function testDeposits() external override runOnForkingNetwork(MAINNET_CHIANID) {
        // poke morpho contract with a deposit to update strategyPrice
        _pokeMorpho();

        uint256 amount = 10000 * ONE_SCALE;
        // AARatio 50%
        idleCDO.depositAA(amount);
        idleCDO.depositBB(amount);

        uint256 strategyPrice = strategy.price();
        // skip rewards and deposit underlyings to the strategy
        _cdoHarvest(true);

        // increase time to accrue some interest
        skip(7 days);
        // Poke morpho contract with a deposit to increase strategyPrice
        _pokeMorpho();

        assertGt(strategy.price(), strategyPrice, "strategy price");
        // claim rewards
        _cdoHarvest(false);
        assertEq(underlying.balanceOf(address(idleCDO)), 0, "underlying bal after harvest");    

        // Skip 7 day forward to accrue interest
        skip(7 days);
        vm.roll(block.number + _strategyReleaseBlocksPeriod() + 1);
        
        // Poke morpho contract with a deposit to increase strategyPrice
        _pokeMorpho();
        assertGt(strategy.price(), strategyPrice, "strategy price");
        // virtualPrice should increase too
        assertGt(idleCDO.virtualPrice(address(AAtranche)), ONE_SCALE, "AA virtual price");
        assertGt(idleCDO.virtualPrice(address(BBtranche)), ONE_SCALE, "BB virtual price");
    }

    function testCantReinitialize() external override runOnForkingNetwork(MAINNET_CHIANID) {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        MorphoAaveV2SupplyVaultStrategy(address(strategy)).initialize(
            "Idle MorphoAaveV2SupplyVaultStrategy DAI",
            "IdleMorphoSupplyVaultStrategy[DAI]",
            maDAI,
            address(underlying),
            owner,
            ADAI,
            address(0)
        );
    }

    function _pokeMorpho() internal {
        uint256 userAmount = 10000 * ONE_SCALE;
        address user = address(0xbabe);
        deal(DAI, user, userAmount);
        vm.startPrank(user);
        IERC20Detailed(DAI).approve(maDAI, type(uint256).max);
        IERC4626(maDAI).deposit(userAmount, user);
        vm.stopPrank();  
    }
}