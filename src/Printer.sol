// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import './Book.sol';
import './interfaces/IPrinter.sol';

//  ,----,------------------------------,------.
//  | ## |                              |    - |
//  | ## |                              |    - |
//  |    |------------------------------|    - |
//  |    ||............................||      |
//  |    ||,-                        -.||      |
//  |    ||___                      ___||    ##|
//  |    ||---`--------------------'---||      |
//  `----'|_|______________________==__|`------'
contract Printer is IPrinter {
    mapping(address => mapping(address => address)) public override pairForERC20; // ERC20 <=> ERC20 pair
    mapping(address => mapping(uint256 => mapping(address => mapping(uint256 => address))))
        public
        override pairForERC1155; // ERC1155 <=> ERC1155 pair
    mapping(address => mapping(uint256 => mapping(address => address))) public override pairForHybrid; // ERC1155 <=> ERC20 pair

    function _sortERC20Tokens(address _tokenA, address _tokenB) internal pure returns (address token0, address token1) {
        if (_tokenA > _tokenB) {
            token0 = _tokenB;
            token1 = _tokenA;
        } else {
            token0 = _tokenA;
            token1 = _tokenB;
        }
    }

    function _sortERC1155Tokens(
        address _tokenA,
        uint256 _idA,
        address _tokenB,
        uint256 _idB
    )
        internal
        pure
        returns (
            address token0,
            uint256 id0,
            address token1,
            uint256 id1
        )
    {
        if (_tokenA == _tokenB) {
            if (_idA > _idB) {
                token0 = _tokenB;
                token1 = _tokenA;
                id0 = _idB;
                id1 = _idA;
            } else {
                token0 = _tokenA;
                token1 = _tokenB;
                id0 = _idA;
                id1 = _idB;
            }
        } else {
            if (_tokenA > _tokenB) {
                token0 = _tokenB;
                token1 = _tokenA;
                id0 = _idB;
                id1 = _idA;
            } else {
                token0 = _tokenA;
                token1 = _tokenB;
                id0 = _idA;
                id1 = _idB;
            }
        }
    }

    function createERC20Pair(address _tokenA, address _tokenB) external override returns (address) {
        if (_tokenA == _tokenB) {
            revert InvalidTokens();
        }

        if (pairForERC20[_tokenA][_tokenB] != address(0)) {
            revert PairAlreadyExists();
        }

        (address token0, address token1) = _sortERC20Tokens(_tokenA, _tokenB);

        Book book = new Book();
        book.initialize(token0, 0, false, token1, 0, false);

        pairForERC20[token0][token1] = address(book);
        pairForERC20[token1][token0] = address(book);

        emit PairCreated(token0, token1, 0, 0, false, false);

        return address(book);
    }

    function createERC1155Pair(
        address _tokenA,
        uint256 _idA,
        address _tokenB,
        uint256 _idB
    ) external override returns (address) {
        if (_tokenA == _tokenB && _idA == _idB) {
            revert InvalidTokens();
        }

        if (pairForERC1155[_tokenA][_idA][_tokenB][_idB] != address(0)) {
            revert PairAlreadyExists();
        }

        (address token0, uint256 id0, address token1, uint256 id1) = _sortERC1155Tokens(_tokenA, _idA, _tokenB, _idB);

        Book book = new Book();
        book.initialize(token0, id0, true, token1, id1, true);

        pairForERC1155[token0][id0][token1][id1] = address(book);
        pairForERC1155[token1][id1][token0][id0] = address(book);

        emit PairCreated(token0, token1, id0, id1, true, true);

        return address(book);
    }

    function createHybridPair(
        address _tokenERC1155,
        uint256 _id,
        address _tokenERC20
    ) external override returns (address) {
        if (_tokenERC20 == _tokenERC1155) {
            revert InvalidTokens();
        }

        if (pairForHybrid[_tokenERC1155][_id][_tokenERC20] != address(0)) {
            revert PairAlreadyExists();
        }

        Book book = new Book();
        book.initialize(_tokenERC1155, _id, true, _tokenERC20, 0, false);

        pairForHybrid[_tokenERC1155][_id][_tokenERC20] = address(book);

        emit PairCreated(_tokenERC1155, _tokenERC20, _id, 0, true, false);

        return address(book);
    }
}
