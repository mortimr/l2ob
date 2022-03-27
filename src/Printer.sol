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
    mapping(address => mapping(address => address)) public override bookForERC20; // ERC20 <=> ERC20 book
    mapping(address => mapping(uint256 => mapping(address => mapping(uint256 => address))))
        public
        override bookForERC1155; // ERC1155 <=> ERC1155 book
    mapping(address => mapping(uint256 => mapping(address => address))) public override bookForHybrid; // ERC1155 <=> ERC20 book

    /// @notice Create Book instance between two ERC20 tokens
    /// @dev Tokens are sorted depending on the value of their address, this means that tokenA does not always equal to token0 in the Book contract.
    /// @param _tokenA Address of the first token
    /// @param _tokenB Address of the second token
    function createERC20Book(address _tokenA, address _tokenB) external override returns (address) {
        if (_tokenA == _tokenB) {
            revert InvalidTokens();
        }

        if (bookForERC20[_tokenA][_tokenB] != address(0)) {
            revert BookAlreadyExists();
        }

        (address token0, address token1) = _sortERC20Tokens(_tokenA, _tokenB);

        Book book = new Book();
        book.initialize(token0, 0, false, token1, 0, false);

        bookForERC20[token0][token1] = address(book);
        bookForERC20[token1][token0] = address(book);

        emit BookCreated(token0, token1, 0, 0, false, false);

        return address(book);
    }

    /// @notice Create Book instance between two ERC1155 tokens
    /// @dev Tokens are sorted depending on the value of their address and their ids, this means that tokenA does not always equal to token0 in the Book contract.
    /// @param _tokenA Address of the first token
    /// @param _idA ERC1155 id of the first token
    /// @param _tokenB Address of the second token
    /// @param _idB ERC1155 id of the second token
    function createERC1155Book(
        address _tokenA,
        uint256 _idA,
        address _tokenB,
        uint256 _idB
    ) external override returns (address) {
        if (_tokenA == _tokenB && _idA == _idB) {
            revert InvalidTokens();
        }

        if (bookForERC1155[_tokenA][_idA][_tokenB][_idB] != address(0)) {
            revert BookAlreadyExists();
        }

        (address token0, uint256 id0, address token1, uint256 id1) = _sortERC1155Tokens(_tokenA, _idA, _tokenB, _idB);

        Book book = new Book();
        book.initialize(token0, id0, true, token1, id1, true);

        bookForERC1155[token0][id0][token1][id1] = address(book);
        bookForERC1155[token1][id1][token0][id0] = address(book);

        emit BookCreated(token0, token1, id0, id1, true, true);

        return address(book);
    }

    /// @notice Create Book instance between an ERC20 token and an ERC1155 token
    /// @dev In hybrid books, the ERC1155 token is always token0
    /// @param _tokenERC1155 Address of the ERC1155 token
    /// @param _id ERC1155 id
    /// @param _tokenERC20 Address of the ERC20 token
    function createHybridBook(
        address _tokenERC1155,
        uint256 _id,
        address _tokenERC20
    ) external override returns (address) {
        if (_tokenERC20 == _tokenERC1155) {
            revert InvalidTokens();
        }

        if (bookForHybrid[_tokenERC1155][_id][_tokenERC20] != address(0)) {
            revert BookAlreadyExists();
        }

        Book book = new Book();
        book.initialize(_tokenERC1155, _id, true, _tokenERC20, 0, false);

        bookForHybrid[_tokenERC1155][_id][_tokenERC20] = address(book);

        emit BookCreated(_tokenERC1155, _tokenERC20, _id, 0, true, false);

        return address(book);
    }

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
}
