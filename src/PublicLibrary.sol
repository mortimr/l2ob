// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import './interfaces/IERC1155.sol';
import './interfaces/IERC20.sol';
import './interfaces/IBook.sol';
import './interfaces/IPrinter.sol';
import './interfaces/IPublicLibrary.sol';

//        .--.                   .---.
//    .---|__|           .-.     |~~~|
// .--|===|--|_          |_|     |erc|--.
// |  |===|  |'\     .---!~|  .--| 1 |--|
// |$$|erc|  |.'\    |===| |--|%%| 1 |  |
// |  | 2 |  |\.'\   |   | |__|  | 5 |  |
// |  | 0 |  | \  \  |===| |==|  | 5 |  |
// |  |   |__|  \.'\ |   |_|__|  |~~~|__|
// |  |===|--|   \.'\|===|~|--|%%|~~~|--|
// ^--^---'--^    `-'`---^-^--^--^---'--'
//
/// @notice PublicLibrary acts as a router between all deployed Books
/// @author Iulian Rotaru
contract PublicLibrary is IPublicLibrary {
    /// @notice Internal decoded swap path element
    struct TokenDetails {
        address tokenAddress;
        uint256 id;
        bool isERC1155;
    }

    /// @notice Global Printer of all Books
    address public override printer;

    /// @notice The only external dependency is the Printer address
    /// @param _printer Address of the Printer
    constructor(address _printer) {
        printer = _printer;
    }

    function getAmountOut(
        uint256 _amountIn,
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut
    ) external view override returns (uint256 amountOut) {
        TokenDetails memory tokenIn = _decodeToken(_tokenIn);
        TokenDetails memory tokenOut = _decodeToken(_tokenOut);
        IBook book = _getBook(tokenIn, tokenOut);
        uint8 tokenOutPos = _getTokenOut(tokenIn, tokenOut);
        return _getMaxAmountOut(book, _amountIn, tokenOutPos);
    }

    function getAmountIn(
        uint256 _amountOut,
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut
    ) external view override returns (uint256 amountIn) {
        TokenDetails memory tokenIn = _decodeToken(_tokenIn);
        TokenDetails memory tokenOut = _decodeToken(_tokenOut);
        IBook book = _getBook(tokenIn, tokenOut);
        uint8 tokenOutPos = _getTokenOut(tokenIn, tokenOut);
        return _getMinAmountIn(book, _amountOut, tokenOutPos);
    }

    function swapExactTokenForToken(
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountOut) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        TokenDetails memory tokenIn = _decodeToken(_tokenIn);
        TokenDetails memory tokenOut = _decodeToken(_tokenOut);
        IBook book = _getBook(tokenIn, tokenOut);
        uint8 tokenOutPos = _getTokenOut(tokenIn, tokenOut);
        amountOut = _getMaxAmountOut(book, _amountIn, tokenOutPos);

        if (amountOut < _amountOutMin) {
            revert AmountOutTooLow(amountOut);
        }

        _transferFrom(tokenIn, msg.sender, address(book), _amountIn);
        book.swap(tokenOutPos == 0 ? amountOut : 0, tokenOutPos == 1 ? amountOut : 0, _to, '');
    }

    function swapTokenForExactToken(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountIn) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        TokenDetails memory tokenIn = _decodeToken(_tokenIn);
        TokenDetails memory tokenOut = _decodeToken(_tokenOut);
        IBook book = _getBook(tokenIn, tokenOut);
        uint8 tokenOutPos = _getTokenOut(tokenIn, tokenOut);
        amountIn = _getMinAmountIn(book, _amountOut, tokenOutPos);

        if (amountIn > _amountInMax) {
            revert AmountInTooHigh(amountIn);
        }

        _transferFrom(tokenIn, msg.sender, address(book), amountIn);
        book.swap(tokenOutPos == 0 ? _amountOut : 0, tokenOutPos == 1 ? _amountOut : 0, _to, '');
    }

    function swapMaxAbovePrice(
        uint256 _amountInMax,
        uint256 _price,
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountIn, uint256 amountOut) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        TokenDetails memory tokenIn = _decodeToken(_tokenIn);
        TokenDetails memory tokenOut = _decodeToken(_tokenOut);
        IBook book = _getBook(tokenIn, tokenOut);
        uint8 tokenOutPos = _getTokenOut(tokenIn, tokenOut);

        (uint64 headIndex, IBook.Order memory order) = tokenOutPos == 0 ? book.head0() : book.head1();

        if (headIndex == 0) {
            revert NullOutput();
        }
        {
            uint8 decimalsIn = tokenOutPos == 0 ? book.decimals1() : book.decimals0();
            uint8 decimalsOut = tokenOutPos == 0 ? book.decimals0() : book.decimals1();

            amountIn = _amountInMax;

            while (amountIn > 0 && order.price >= _price) {
                uint256 availableLiquidity = order.remainingLiquidity + order.nextLiquidity;
                uint256 amountInRequired = _getAmountIn(availableLiquidity, order.price, decimalsIn + decimalsOut);

                if (amountInRequired >= amountIn) {
                    uint256 _localAmountOut = _getAmountOut(amountIn, order.price, decimalsIn + decimalsOut);
                    amountIn -= _getAmountIn(_localAmountOut, order.price, decimalsIn + decimalsOut);
                    amountOut += _localAmountOut;
                    break;
                } else {
                    amountOut += _getAmountOut(amountInRequired, order.price, decimalsIn + decimalsOut);
                    amountIn -= amountInRequired;
                }

                if (order.next == 0) {
                    break;
                } else {
                    order = book.orders(order.next);
                }
            }
        }

        amountIn = _amountInMax - amountIn;

        if (amountOut == 0) {
            revert NullOutput();
        }

        _transferFrom(tokenIn, msg.sender, address(book), amountIn);
        book.swap(tokenOutPos == 0 ? amountOut : 0, tokenOutPos == 1 ? amountOut : 0, _to, '');
    }

    /// @notice Get array of amounts for swap path for an exact input amount
    /// @dev amounts[0] is the input amount
    /// @dev amounts[amounts.length - 1] is the final output amount of the trade
    /// @dev _path is an encoded path argument that can contain both ERC20 and ERC1155 tokens
    /// @dev An ERC20 encoded element consists of [0, uint256(tokenAddress)]
    /// @dev An ERC1155 encoded element consists of [1, uint256(tokenAddress), uint256(tokenId)]
    /// @dev The amounts length is equal to the number of elements in the path, not the raw number of values in the path
    /// @param _amountIn Exact amount in provided to swap path
    /// @param _path Encoded swap path argument
    function getAmountsOut(uint256 _amountIn, uint256[] calldata _path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        TokenDetails[] memory td = _pathToTokenDetails(_path);
        return _getAmountsOut(td, _amountIn);
    }

    /// @notice Get array of amounts for swap path for an exact output amount
    /// @dev amounts[0] is the input amount
    /// @dev amounts[amounts.length - 1] is the final output amount of the trade
    /// @dev _path is an encoded path argument that can contain both ERC20 and ERC1155 tokens
    /// @dev An ERC20 encoded element consists of [0, uint256(tokenAddress)]
    /// @dev An ERC1155 encoded element consists of [1, uint256(tokenAddress), uint256(tokenId)]
    /// @dev The amounts length is equal to the number of elements in the path, not the raw number of values in the path
    /// @param _amountOut Exact amount out expected from swap path
    /// @param _path Encoded swap path argument
    function getAmountsIn(uint256 _amountOut, uint256[] calldata _path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        TokenDetails[] memory td = _pathToTokenDetails(_path);
        return _getAmountsIn(td, _amountOut);
    }

    /// @notice Execute swap path for exact input amount
    /// @dev amounts[0] is the input amount
    /// @dev amounts[amounts.length - 1] is the final output amount of the trade
    /// @dev _path is an encoded path argument that can contain both ERC20 and ERC1155 tokens
    /// @dev An ERC20 encoded element consists of [0, uint256(tokenAddress)]
    /// @dev An ERC1155 encoded element consists of [1, uint256(tokenAddress), uint256(tokenId)]
    /// @dev The amounts length is equal to the number of elements in the path, not the raw number of values in the path
    /// @param _amountIn Exact amount in provided
    /// @param _amountOutMin Minimal expected output amount
    /// @param _path Encoded swap path argument
    /// @param _to Swap output recipient
    /// @param _deadline Timestamp after which swap is invalid
    function swapExactIn(
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256[] calldata _path,
        address _to,
        uint256 _deadline
    ) external override returns (uint256[] memory amounts) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        if (_path.length < 2) {
            revert InvalidArrayLength();
        }

        TokenDetails[] memory tokenDetails = _pathToTokenDetails(_path);
        amounts = _getAmountsOut(tokenDetails, _amountIn);

        if (amounts[amounts.length - 1] < _amountOutMin) {
            revert AmountOutTooLow(amounts[amounts.length - 1]);
        }

        _executeSwapPath(tokenDetails, amounts, _to);
    }

    /// @notice Execute swap path for exact output amount
    /// @dev amounts[0] is the input amount
    /// @dev amounts[amounts.length - 1] is the final output amount of the trade
    /// @dev _path is an encoded path argument that can contain both ERC20 and ERC1155 tokens
    /// @dev An ERC20 encoded element consists of [0, uint256(tokenAddress)]
    /// @dev An ERC1155 encoded element consists of [1, uint256(tokenAddress), uint256(tokenId)]
    /// @dev The amounts length is equal to the number of elements in the path, not the raw number of values in the path
    /// @param _amountOut Exact amount out expected
    /// @param _amountInMax Maximal expected input amount
    /// @param _path Encoded swap path argument
    /// @param _to Swap output recipient
    /// @param _deadline Timestamp after which swap is invalid
    function swapExactOut(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[] calldata _path,
        address _to,
        uint256 _deadline
    ) external override returns (uint256[] memory amounts) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        if (_path.length < 2) {
            revert InvalidArrayLength();
        }

        TokenDetails[] memory tokenDetails = _pathToTokenDetails(_path);
        amounts = _getAmountsIn(tokenDetails, _amountOut);

        if (amounts[0] > _amountInMax) {
            revert AmountInTooHigh(amounts[0]);
        }

        _executeSwapPath(tokenDetails, amounts, _to);
    }

    function open(
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external override returns (address book, uint256 orderId) {
        TokenDetails memory tokenIn = _decodeToken(_tokenIn);
        TokenDetails memory tokenOut = _decodeToken(_tokenOut);
        book = address(_getBook(tokenIn, tokenOut));
        if (book == address(0)) {
            book = address(_createBook(tokenIn, tokenOut));
        }

        _transferFrom(tokenOut, msg.sender, book, _amount);
        IBook(book).open(_price, _nextOrderIndex, msg.sender);
        uint8 tokenOutPos = _getTokenOut(tokenIn, tokenOut);
        orderId = _getOrderId(tokenOutPos, _price);
    }

    /// @notice Closes an order position
    /// @dev If order is partially filled, a mix between order input and order output token will be claimed
    /// @dev If order is completely filled, only output token will be claimed
    /// @dev If order is untouched, only initial order input token will be claimed
    /// @dev User must approve at least _amount order tokens to this contract
    /// @param _book Address of the Book where the order is owned
    /// @param _id Order id
    /// @param _amount Order amount to close
    function closeOrder(
        address _book,
        uint256 _id,
        uint256 _amount
    ) external override {
        IERC1155(_book).safeTransferFrom(msg.sender, address(_book), _id, _amount, '');
        IBook(_book).close(_id, msg.sender);
    }

    /// @notice Settles multiple order on multiple books
    /// @dev Settling an order will withdraw the filled amounts for every order and keep the remaining active
    /// @param _books Array of books on which to settle orders
    /// @param _orderCounts Array of order counts for each book
    /// @param _orderIds Array of order id, length is equal to the sum of _orderCounts
    /// @param _owner Owner of the orders
    function settle(
        address[] calldata _books,
        uint256[] calldata _orderCounts,
        uint256[] calldata _orderIds,
        address _owner
    ) external override {
        if (_books.length != _orderCounts.length || _books.length == 0) {
            revert InvalidArrayLength();
        }

        uint256 idIndex = 0;

        for (uint256 i; i < _books.length; ) {
            uint256[] memory ids = new uint256[](_orderCounts[i]);
            for (uint256 y; y < _orderCounts[i]; ) {
                ids[y] = _orderIds[idIndex + y];
                unchecked {
                    ++y;
                }
            }
            IBook(_books[i]).settle(_owner, ids);
            unchecked {
                idIndex += _orderCounts[i];
                ++i;
            }
        }
    }

    //
    // ██╗███╗   ██╗████████╗███████╗██████╗ ███╗   ██╗ █████╗ ██╗     ███████╗
    // ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗████╗  ██║██╔══██╗██║     ██╔════╝
    // ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝██╔██╗ ██║███████║██║     ███████╗
    // ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██║╚██╗██║██╔══██║██║     ╚════██║
    // ██║██║ ╚████║   ██║   ███████╗██║  ██║██║ ╚████║██║  ██║███████╗███████║
    // ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝╚══════╝
    //

    function _decodeToken(uint256[3] calldata _token) internal pure returns (TokenDetails memory) {
        return
            TokenDetails({
                tokenAddress: _uintToAddress(_token[1]),
                id: _token[0] == 1 ? _token[2] : 0,
                isERC1155: _token[0] == 1
            });
    }

    function _getBook(TokenDetails memory _tokenA, TokenDetails memory _tokenB) internal view returns (IBook) {
        if (!_tokenA.isERC1155 && !_tokenB.isERC1155) {
            return IBook(IPrinter(printer).bookForERC20(_tokenA.tokenAddress, _tokenB.tokenAddress));
        } else if (_tokenA.isERC1155 && !_tokenB.isERC1155) {
            return IBook(IPrinter(printer).bookForHybrid(_tokenA.tokenAddress, _tokenA.id, _tokenB.tokenAddress));
        } else if (!_tokenA.isERC1155 && _tokenB.isERC1155) {
            return IBook(IPrinter(printer).bookForHybrid(_tokenB.tokenAddress, _tokenB.id, _tokenA.tokenAddress));
        } else {
            return
                IBook(
                    IPrinter(printer).bookForERC1155(_tokenA.tokenAddress, _tokenA.id, _tokenB.tokenAddress, _tokenB.id)
                );
        }
    }

    function _createBook(TokenDetails memory _tokenA, TokenDetails memory _tokenB) internal returns (IBook) {
        if (!_tokenA.isERC1155 && !_tokenB.isERC1155) {
            return IBook(IPrinter(printer).createERC20Book(_tokenA.tokenAddress, _tokenB.tokenAddress));
        } else if (_tokenA.isERC1155 && !_tokenB.isERC1155) {
            return IBook(IPrinter(printer).createHybridBook(_tokenA.tokenAddress, _tokenA.id, _tokenB.tokenAddress));
        } else if (!_tokenA.isERC1155 && _tokenB.isERC1155) {
            return IBook(IPrinter(printer).createHybridBook(_tokenB.tokenAddress, _tokenB.id, _tokenA.tokenAddress));
        } else {
            return
                IBook(
                    IPrinter(printer).createERC1155Book(
                        _tokenA.tokenAddress,
                        _tokenA.id,
                        _tokenB.tokenAddress,
                        _tokenB.id
                    )
                );
        }
    }

    function _getTokenOut(TokenDetails memory _tokenIn, TokenDetails memory _tokenOut) internal pure returns (uint8) {
        if (!_tokenIn.isERC1155 && !_tokenOut.isERC1155) {
            return _tokenOut.tokenAddress < _tokenIn.tokenAddress ? 0 : 1;
        } else if (_tokenIn.isERC1155 && !_tokenOut.isERC1155) {
            return 1;
        } else if (!_tokenIn.isERC1155 && _tokenOut.isERC1155) {
            return 0;
        } else {
            return
                (
                    _tokenIn.tokenAddress == _tokenOut.tokenAddress
                        ? _tokenOut.id < _tokenIn.id
                        : _tokenOut.tokenAddress < _tokenIn.tokenAddress
                )
                    ? 0
                    : 1;
        }
    }

    function _transferFrom(
        TokenDetails memory _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (!_token.isERC1155) {
            IERC20(_token.tokenAddress).transferFrom(_from, _to, _amount);
        } else {
            IERC1155(_token.tokenAddress).safeTransferFrom(_from, _to, _token.id, _amount, '');
        }
    }

    function _getOrderId(uint8 _token, uint256 _price) internal pure returns (uint256 id) {
        id = _price << 1;
        if (_token == 1) {
            id += 1;
        }
        id = id << 1;
    }

    function _getAmountIn(
        uint256 _amountOut,
        uint256 _price,
        uint8 _decimals
    ) internal pure returns (uint256) {
        return ((_amountOut * (10**_decimals)) / _price);
    }

    function _getAmountOut(
        uint256 _amountIn,
        uint256 _price,
        uint8 _decimals
    ) internal pure returns (uint256) {
        return ((_amountIn * _price) / 10**_decimals);
    }

    function _getMaxAmountOut(
        IBook _book,
        uint256 _amountIn,
        uint8 _tokenOut
    ) internal view returns (uint256 amountOut) {
        (uint64 headIndex, IBook.Order memory order) = _tokenOut == 0 ? _book.head0() : _book.head1();
        if (headIndex == 0) {
            revert InsufficientLiquidity(address(_book), _tokenOut, _amountIn);
        }
        uint8 decimalIn = _tokenOut == 0 ? _book.decimals1() : _book.decimals0();
        uint8 decimalOut = _tokenOut == 0 ? _book.decimals0() : _book.decimals1();
        while (_amountIn > 0) {
            uint256 minAmountIn = _getAmountIn(
                order.remainingLiquidity + order.nextLiquidity,
                order.price,
                decimalIn + decimalOut
            );
            if (minAmountIn >= _amountIn) {
                amountOut += _getAmountOut(_amountIn, order.price, decimalIn + decimalOut);
                _amountIn = 0;
            } else {
                amountOut += _getAmountOut(minAmountIn, order.price, decimalIn + decimalOut);
                _amountIn -= minAmountIn;
                if (order.next == 0) {
                    revert InsufficientLiquidity(address(_book), _tokenOut, _amountIn);
                }
                order = _book.orders(order.next);
            }
        }
    }

    function _getMinAmountIn(
        IBook _book,
        uint256 _amountOut,
        uint8 _tokenOut
    ) internal view returns (uint256 amountIn) {
        (uint64 headIndex, IBook.Order memory order) = _tokenOut == 0 ? _book.head0() : _book.head1();
        if (headIndex == 0) {
            revert InsufficientLiquidity(address(_book), _tokenOut, _amountOut);
        }
        uint8 decimalIn = _tokenOut == 0 ? _book.decimals1() : _book.decimals0();
        uint8 decimalOut = _tokenOut == 0 ? _book.decimals0() : _book.decimals1();
        while (_amountOut > 0) {
            uint256 maxAmountOut = order.remainingLiquidity + order.nextLiquidity;
            if (maxAmountOut >= _amountOut) {
                amountIn += _getAmountIn(_amountOut, order.price, decimalIn + decimalOut);
                _amountOut = 0;
            } else {
                amountIn += _getAmountIn(
                    order.remainingLiquidity + order.nextLiquidity,
                    order.price,
                    decimalIn + decimalOut
                );
                _amountOut -= maxAmountOut;
                if (order.next == 0) {
                    revert InsufficientLiquidity(address(_book), _tokenOut, _amountOut);
                }
                order = _book.orders(order.next);
            }
        }
    }

    function _isERC20Token0(address _tokenA, address _tokenB) internal pure returns (bool) {
        return _tokenA < _tokenB;
    }

    function _isERC1155Token0(
        address _tokenA,
        uint256 _idA,
        address _tokenB,
        uint256 _idB
    ) internal pure returns (bool) {
        if (_tokenA == _tokenB) {
            return _idA < _idB;
        }
        return _tokenA < _tokenB;
    }

    function _getAmountsOut(TokenDetails[] memory _path, uint256 _amountIn)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](_path.length);

        for (uint256 i; i < _path.length - 1; ) {
            amounts[i] = _amountIn;
            if (_path[i].isERC1155 == false && _path[i + 1].isERC1155 == false) {
                _amountIn = _getMaxAmountOut(
                    IBook(IPrinter(printer).bookForERC20(_path[i].tokenAddress, _path[i + 1].tokenAddress)),
                    _amountIn,
                    _isERC20Token0(_path[i].tokenAddress, _path[i + 1].tokenAddress) == true ? 1 : 0
                );
            } else if (_path[i].isERC1155 == true && _path[i + 1].isERC1155 == true) {
                _amountIn = _getMaxAmountOut(
                    IBook(
                        IPrinter(printer).bookForERC1155(
                            _path[i].tokenAddress,
                            _path[i].id,
                            _path[i + 1].tokenAddress,
                            _path[i + 1].id
                        )
                    ),
                    _amountIn,
                    _isERC1155Token0(_path[i].tokenAddress, _path[i].id, _path[i + 1].tokenAddress, _path[i + 1].id) ==
                        true
                        ? 1
                        : 0
                );
            } else if (_path[i].isERC1155 == true && _path[i + 1].isERC1155 == false) {
                _amountIn = _getMaxAmountOut(
                    IBook(
                        IPrinter(printer).bookForHybrid(_path[i].tokenAddress, _path[i].id, _path[i + 1].tokenAddress)
                    ),
                    _amountIn,
                    1
                );
            } else if (_path[i].isERC1155 == false && _path[i + 1].isERC1155 == true) {
                _amountIn = _getMaxAmountOut(
                    IBook(
                        IPrinter(printer).bookForHybrid(
                            _path[i + 1].tokenAddress,
                            _path[i + 1].id,
                            _path[i].tokenAddress
                        )
                    ),
                    _amountIn,
                    0
                );
            }

            unchecked {
                ++i;
            }
        }

        amounts[_path.length - 1] = _amountIn;
    }

    function _getAmountsIn(TokenDetails[] memory _path, uint256 _amountOut)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](_path.length);

        for (uint256 i = _path.length - 1; i >= 1; ) {
            amounts[i] = _amountOut;
            if (_path[i].isERC1155 == false && _path[i - 1].isERC1155 == false) {
                _amountOut = _getMinAmountIn(
                    IBook(IPrinter(printer).bookForERC20(_path[i].tokenAddress, _path[i - 1].tokenAddress)),
                    _amountOut,
                    _isERC20Token0(_path[i].tokenAddress, _path[i - 1].tokenAddress) == true ? 0 : 1
                );
            } else if (_path[i].isERC1155 == true && _path[i - 1].isERC1155 == true) {
                _amountOut = _getMinAmountIn(
                    IBook(
                        IPrinter(printer).bookForERC1155(
                            _path[i].tokenAddress,
                            _path[i].id,
                            _path[i - 1].tokenAddress,
                            _path[i - 1].id
                        )
                    ),
                    _amountOut,
                    _isERC1155Token0(_path[i].tokenAddress, _path[i].id, _path[i - 1].tokenAddress, _path[i - 1].id) ==
                        true
                        ? 1
                        : 0
                );
            } else if (_path[i].isERC1155 == true && _path[i - 1].isERC1155 == false) {
                _amountOut = _getMinAmountIn(
                    IBook(
                        IPrinter(printer).bookForHybrid(_path[i].tokenAddress, _path[i].id, _path[i - 1].tokenAddress)
                    ),
                    _amountOut,
                    0
                );
            } else if (_path[i].isERC1155 == false && _path[i - 1].isERC1155 == true) {
                _amountOut = _getMinAmountIn(
                    IBook(
                        IPrinter(printer).bookForHybrid(
                            _path[i - 1].tokenAddress,
                            _path[i - 1].id,
                            _path[i].tokenAddress
                        )
                    ),
                    _amountOut,
                    1
                );
            }
            unchecked {
                --i;
            }
        }

        amounts[0] = _amountOut;
    }

    function _uintToAddress(uint256 _v) internal pure returns (address a) {
        assembly {
            a := _v
        }
    }

    function _pathToTokenDetails(uint256[] calldata _path) internal pure returns (TokenDetails[] memory tokenDetails) {
        uint256 count;
        for (uint256 i; i < _path.length; ) {
            if (_path[i] == 0) {
                // erc1155
                ++i;
            } else {
                i += 1;
            }

            ++count;

            unchecked {
                ++i;
            }
        }
        tokenDetails = new TokenDetails[](count);
        count = 0;

        for (uint256 i; i < _path.length; ) {
            if (_path[i] == 0) {
                tokenDetails[count] = TokenDetails({
                    tokenAddress: _uintToAddress(_path[i + 1]),
                    id: 0,
                    isERC1155: false
                });
                ++i;
            } else {
                tokenDetails[count] = TokenDetails({
                    tokenAddress: _uintToAddress(_path[i + 1]),
                    id: _path[i + 2],
                    isERC1155: true
                });
                i += 2;
            }

            ++count;

            unchecked {
                ++i;
            }
        }
    }

    function _getAddress(TokenDetails memory _tokenIn, TokenDetails memory _tokenOut) internal view returns (address) {
        if (_tokenIn.isERC1155 != _tokenOut.isERC1155) {
            if (_tokenIn.isERC1155 == true) {
                return IPrinter(printer).bookForHybrid(_tokenIn.tokenAddress, _tokenIn.id, _tokenOut.tokenAddress);
            } else {
                return IPrinter(printer).bookForHybrid(_tokenOut.tokenAddress, _tokenOut.id, _tokenIn.tokenAddress);
            }
        } else {
            if (_tokenIn.isERC1155 == true) {
                return
                    IPrinter(printer).bookForERC1155(
                        _tokenIn.tokenAddress,
                        _tokenIn.id,
                        _tokenOut.tokenAddress,
                        _tokenOut.id
                    );
            } else {
                return IPrinter(printer).bookForERC20(_tokenIn.tokenAddress, _tokenOut.tokenAddress);
            }
        }
    }

    function _executeSwap(
        IBook _book,
        TokenDetails memory _tokenIn,
        TokenDetails memory _tokenOut,
        uint256 _amountOut,
        address _recipient
    ) internal {
        if (_tokenIn.isERC1155 != _tokenOut.isERC1155) {
            if (_tokenIn.isERC1155 == true) {
                // in is token0
                _book.swap(0, _amountOut, _recipient, '');
            } else {
                // out is token0
                _book.swap(_amountOut, 0, _recipient, '');
            }
        } else {
            if (_tokenIn.isERC1155 == true) {
                // both are 1155

                if (_book.token0() == _tokenIn.tokenAddress && _book.id0() == _tokenIn.id) {
                    // in is token0
                    _book.swap(0, _amountOut, _recipient, '');
                } else {
                    // out is token0
                    _book.swap(_amountOut, 0, _recipient, '');
                }
            } else {
                // both are 20

                if (_book.token0() == _tokenIn.tokenAddress) {
                    // in is token0
                    _book.swap(0, _amountOut, _recipient, '');
                } else {
                    // out is token0
                    _book.swap(_amountOut, 0, _recipient, '');
                }
            }
        }
    }

    function _transfer(
        TokenDetails memory _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_token.isERC1155) {
            IERC1155(_token.tokenAddress).safeTransferFrom(_from, _to, _token.id, _amount, '');
        } else {
            IERC20(_token.tokenAddress).transferFrom(_from, _to, _amount);
        }
    }

    function _executeSwapPath(
        TokenDetails[] memory _tokenDetails,
        uint256[] memory _amounts,
        address _to
    ) internal {
        address currentAddress = _getAddress(_tokenDetails[0], _tokenDetails[1]);
        address recipientAddress;

        _transfer(_tokenDetails[0], msg.sender, currentAddress, _amounts[0]);

        for (uint256 i; i < _tokenDetails.length - 1; ) {
            if (i + 1 == _tokenDetails.length - 1) {
                recipientAddress = _to;
            } else {
                recipientAddress = _getAddress(_tokenDetails[i + 1], _tokenDetails[i + 2]);
            }

            _executeSwap(
                IBook(currentAddress),
                _tokenDetails[i],
                _tokenDetails[i + 1],
                _amounts[i + 1],
                recipientAddress
            );

            currentAddress = recipientAddress;

            unchecked {
                ++i;
            }
        }
    }
}
