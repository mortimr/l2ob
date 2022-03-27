// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import './interfaces/IBook.sol';
import './interfaces/IPrinter.sol';

//  ,----,------------------------------,------.
//  | ## |           STARKNET           |    - |
//  | ## |                              |    - |
//  |    |------------------------------|    - |
//  |    ||............................||      |
//  |    ||,-                        -.||      |
//  |    ||___                      ___||    ##|
//  |    ||---`--------------------'---||      |
//  `----'|_|______________________==__|`------'
contract StarknetPrinter is IPrinter {
    event PairRequested(address token0, address token1, uint256 id0, uint256 id1, bool isERC1155_0, bool isERC1155_1);

    mapping(address => mapping(address => address)) public override pairForERC20; // ERC20 <=> ERC20 pair
    mapping(address => mapping(uint256 => mapping(address => mapping(uint256 => address))))
        public
        override pairForERC1155; // ERC1155 <=> ERC1155 pair
    mapping(address => mapping(uint256 => mapping(address => address))) public override pairForHybrid; // ERC1155 <=> ERC20 pair
    address public deployer;

    constructor(address _deployer) {
        deployer = _deployer;
    }

    /// @notice The deploy is the address allowed to set the pairs after seeing PairRequested events
    /// @dev This is a workaround until CREATE becomes possible on Starknet
    modifier onlyDeployer() {
        require(msg.sender == deployer, 'unauthorized');
        _;
    }

    /// @notice Create Book instance between two ERC20 tokens
    /// @dev Tokens are sorted depending on the value of their address, this means that tokenA does not always equal to token0 in the Book contract.
    /// @dev Due to some Starknet limitations, pairs are created in a async manner. Do not rely on the output of this method.
    /// @param _tokenA Address of the first token
    /// @param _tokenB Address of the second token
    function createERC20Pair(address _tokenA, address _tokenB) external override returns (address) {
        if (_tokenA == _tokenB) {
            revert InvalidTokens();
        }

        if (pairForERC20[_tokenA][_tokenB] != address(0)) {
            revert PairAlreadyExists();
        }

        (address token0, address token1) = _sortERC20Tokens(_tokenA, _tokenB);

        emit PairRequested(token0, token1, 0, 0, false, false);

        return (address(0));
    }

    /// @notice Create Book instance between two ERC1155 tokens
    /// @dev Tokens are sorted depending on the value of their address and their ids, this means that tokenA does not always equal to token0 in the Book contract.
    /// @dev Due to some Starknet limitations, pairs are created in a async manner. Do not rely on the output of this method.
    /// @param _tokenA Address of the first token
    /// @param _idA ERC1155 id of the first token
    /// @param _tokenB Address of the second token
    /// @param _idB ERC1155 id of the second token
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

        emit PairRequested(token0, token1, id0, id1, true, true);

        return address(0);
    }

    /// @notice Create Book instance between an ERC20 token and an ERC1155 token
    /// @dev In hybrid pairs, the ERC1155 token is always token0
    /// @dev Due to some Starknet limitations, pairs are created in a async manner. Do not rely on the output of this method.
    /// @param _tokenERC1155 Address of the ERC1155 token
    /// @param _id ERC1155 id
    /// @param _tokenERC20 Address of the ERC20 token
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

        emit PairRequested(_tokenERC1155, _tokenERC20, _id, 0, true, false);

        return address(0);
    }

    function _deployedERC20Pair(address book) external onlyDeployer {
        address token0 = IBook(book).token0();
        address token1 = IBook(book).token1();

        pairForERC20[token0][token1] = book;
        pairForERC20[token1][token0] = book;

        emit PairCreated(token0, token1, 0, 0, false, false);
    }

    function _deployedERC1155Pair(address book) external onlyDeployer {
        address token0 = IBook(book).token0();
        uint256 id0 = IBook(book).id0();
        address token1 = IBook(book).token1();
        uint256 id1 = IBook(book).id1();

        pairForERC1155[token0][id0][token1][id1] = book;
        pairForERC1155[token1][id1][token0][id0] = book;

        emit PairCreated(token0, token1, id0, id1, true, true);
    }

    function _deployedHybridPair(address book) external onlyDeployer {
        address token0 = IBook(book).token0();
        uint256 id0 = IBook(book).id0();
        address token1 = IBook(book).token1();

        pairForHybrid[token0][id0][token1] = book;

        emit PairCreated(token0, token1, id0, 0, true, false);
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
