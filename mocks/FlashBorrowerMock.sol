// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;
import {IERC3156FlashBorrower} from "@openzeppelin/contracts@v5.0.2/interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "@openzeppelin/contracts@v5.0.2/token/ERC20/IERC20.sol";

contract FlashBorrowerMock is IERC3156FlashBorrower {
    address internal immutable lender;
    address internal immutable allowedInitiator;
    bool internal returnEnoughFee;
    bytes32 internal immutable returnHash;

    constructor(
        address _lender,
        address _initiator,
        bool _returnEnoughFee,
        bytes32 _returnHash
    ) {
        lender = _lender;
        allowedInitiator = _initiator;
        returnEnoughFee = _returnEnoughFee;
        returnHash = _returnHash;
    }

    // for excluding from coverage report
    function test() public {}

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata /*data*/
    ) external override returns (bytes32) {
        require(
            initiator == allowedInitiator,
            "FlashBorrowerMock: initiator is not self"
        );
        require(msg.sender == lender, "FlashBorrowerMock: not lender");

        uint256 amountToApprove = 0;
        if (returnEnoughFee) {
            amountToApprove = amount + fee;
        } else {
            amountToApprove = amount;
        }
        IERC20(token).approve(lender, amountToApprove);

        return returnHash;
    }
}
