// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";
import "@openzeppelinV3/contracts/math/Math.sol";
import "@openzeppelinV3/contracts/utils/Address.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";

import "../../interfaces/yearn/Vault.sol";

contract IndexWeth is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public weth;
    address public yvWeth;
    string public constant override name = "IndexWeth";

    constructor(
        address _vault,
        address _weth,
        address _yvWeth
    ) public BaseStrategy(_vault) {
        weth = _weth;
        yvWeth = _yvWeth;

        IERC20(weth).safeApprove(yvWeth, uint256(-1));
    }

    function protectedTokens() internal override view returns (address[] memory) {
        address[] memory protected = new address[](1);
        // want is weth, which is protected by default
        protected[0] = yvWeth;
        return protected;
    }

    function estimatedTotalAssets() public override view returns (uint256) {
        return balanceOfWant().add(balanceOfStake());
    }

    function prepareReturn(uint256 _debtOutstanding) internal override returns (uint256 _profit, uint256 _loss, uint256 _debtPayment) {
        // We might need to return want to the vault
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }

        uint256 balanceOfWantBefore = balanceOfWant();

        _profit = balanceOfWant().sub(balanceOfWantBefore);
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        uint256 _wantAvailable = balanceOfWant().sub(_debtOutstanding);

        if (_wantAvailable > 0) {
            Vault(yvWeth).deposit(_wantAvailable);
        }
    }

    function exitPosition(uint256 _debtOutstanding)
        internal
        override
        returns (
          uint256 _profit,
          uint256 _loss,
          uint256 _debtPayment
        )
    {

        Vault(yvWeth).withdrawAll();
        return prepareReturn(_debtOutstanding);
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _amountFreed) {
        if (balanceOfWant() < _amountNeeded) {
            // We need to sell stakes to get back more want
            _withdrawSome(_amountNeeded.sub(balanceOfWant()));
        }

        _amountFreed = balanceOfWant();
    }

    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 vaultShare = Vault(yvWeth).getPricePerFullShare();
        uint256 vaultWithdraw = vaultShare.div(vaultShare);
        Vault(yvWeth).withdraw(vaultWithdraw);
        return balanceOfWant();
    }

    function prepareMigration(address _newStrategy) internal override {
        want.transfer(_newStrategy, balanceOfWant());
        IERC20(yvWeth).transfer(_newStrategy, IERC20(yvWeth).balanceOf(address(this)));
    }



    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfStake() public view returns (uint256) {
        uint256 vaultShares = IERC20(yvWeth).balanceOf(address(this));
        uint256 vaultPrice = Vault(yvWeth).getPricePerFullShare();
        uint256 vaultBalance = vaultShares.mul(vaultPrice);
        return vaultBalance;
    }
}
