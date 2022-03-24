// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

interface IBook {
    function open(
        uint256 _price,
        uint64 _nextOrderIndex,
        address _to
    ) external;

    function close(uint256 _orderId, address _to) external;
}
