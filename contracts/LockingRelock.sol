// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./LockingBase.sol";

abstract contract LockingRelock is LockingBase {
    using LibBrokenLine for LibBrokenLine.BrokenLine;

    function relock(uint id, address newDelegate, uint96 newAmount, uint32 newSlopePeriod, uint32 newCliff) external notStopped notMigrating returns (uint) {
        address account = verifyLockOwner(id);
        uint32 currentBlock = getBlockNumber();
        uint32 time = roundTimestamp(currentBlock);
        verification(account, id, newAmount, newSlopePeriod, newCliff, time);

        address _delegate = locks[id].delegate;
        accounts[account].locked.update(time);

        rebalance(id, account, accounts[account].locked.initial.bias, removeLines(id, account, _delegate, time), newAmount);

        counter++;

        addLines(account, newDelegate, newAmount, newSlopePeriod, newCliff, time, currentBlock);
        emit Relock(id, account, newDelegate, counter, time, newAmount, newSlopePeriod, newCliff);

        return counter;
    }

    /**
     * @dev Verification parameters:
     *      1. amount > 0, slope > 0
     *      2. cliff period and slope period less or equal two years
     *      3. newFinishTime more or equal oldFinishTime
     */
    function verification(address account, uint id, uint96 newAmount, uint32 newSlopePeriod, uint32 newCliff, uint32 toTime) internal view {
        require(newAmount > 0, "zero amount");
        require(newCliff <= MAX_CLIFF_PERIOD, "cliff too big");
        require(newSlopePeriod <= MAX_SLOPE_PERIOD, "slope period too big");
        require(newSlopePeriod > 0, "slope period equal 0");

        //check Line with new parameters don`t finish earlier than old Line
        uint32 newEnd = toTime + (newCliff) + (newSlopePeriod);
        LibBrokenLine.Line memory line = accounts[account].locked.initiatedLines[id];
        uint32 oldSlopePeriod = uint32(divUp(line.bias, line.slope));
        uint32 oldEnd = line.start + (line.cliff) + (oldSlopePeriod);
        require(oldEnd <= newEnd, "new line period lock too short");

        //check Line with new parameters don`t cut corner old Line
        uint32 oldCliffEnd = line.start + (line.cliff);
        uint32 newCliffEnd = toTime + (newCliff);
        if (oldCliffEnd > newCliffEnd) {
            uint32 balance = oldCliffEnd - (newCliffEnd);
            uint32 newSlope = uint32(divUp(newAmount, newSlopePeriod));
            uint96 newBias = newAmount - (balance * (newSlope));
            require(newBias >= line.bias, "detect cut deposit corner");
        }
    }

    function removeLines(uint id, address account, address delegate, uint32 toTime) internal returns (uint96 residue) {
        updateLines(account, delegate, toTime);
        uint32 currentBlock = getBlockNumber();
        accounts[delegate].balance.remove(id, toTime, currentBlock);
        totalSupplyLine.remove(id, toTime, currentBlock);
        (residue,,) = accounts[account].locked.remove(id, toTime, currentBlock);
    }

    function rebalance(uint id, address account, uint96 bias, uint96 residue, uint96 newAmount) internal {
        require(residue <= newAmount, "Impossible to relock: less amount, then now is");
        uint96 addAmount = newAmount - (residue);
        uint96 amount = accounts[account].amount;
        uint96 balance = amount - (bias);
        if (addAmount > balance) {
            //need more, than balance, so need transfer tokens to this
            uint96 transferAmount = addAmount - (balance);
            accounts[account].amount = accounts[account].amount + (transferAmount);
            require(token.transferFrom(locks[id].account, address(this), transferAmount), "transfer failed");
        }
    }

    uint256[50] private __gap;
}
