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

    function pairForERC20(address _tokenA, address _tokenB) external view returns (address);

    function pairForERC1155(
        address _tokenA,
        uint256 _idA,
        address _tokenB,
        uint256 _idB
    ) external view returns (address);

    function pairForHybrid(
        address _tokenERC1155,
        uint256 _id,
        address _tokenERC20
    ) external view returns (address);

    function createERC20Pair(address _tokenA, address _tokenB) external returns (address);

    function createERC1155Pair(
        address _tokenA,
        uint256 _idA,
        address _tokenB,
        uint256 _idB
    ) external returns (address);

    function createHybridPair(
        address _tokenERC1155,
        uint256 _id,
        address _tokenERC20
    ) external returns (address);
}
