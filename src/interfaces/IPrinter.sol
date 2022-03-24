// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

interface IPrinter {
    function pairForERC20(address, address) external returns (address);

    function pairForERC1155(
        address,
        uint256,
        address,
        uint256
    ) external returns (address);

    function pairForHybrid(
        address,
        uint256,
        address
    ) external returns (address);

    function createERC20Pair(address, address) external returns (address);

    function createERC1155Pair(
        address,
        uint256,
        address,
        uint256
    ) external returns (address);

    function createHybridPair(
        address,
        uint256,
        address
    ) external returns (address);
}
