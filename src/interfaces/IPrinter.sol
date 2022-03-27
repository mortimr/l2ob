// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

interface IPrinter {
    error PairAlreadyExists();
    error InvalidTokens();
    event PairCreated(
        address indexed _token0,
        address indexed _token1,
        uint256 _id0,
        uint256 _id1,
        bool _erc1155_0,
        bool _erc1155_1
    );

    function pairForERC20(address, address) external view returns (address);

    function pairForERC1155(
        address,
        uint256,
        address,
        uint256
    ) external view returns (address);

    function pairForHybrid(
        address,
        uint256,
        address
    ) external view returns (address);

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
