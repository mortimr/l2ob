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
contract PublicLibrary is IPublicLibrary {
    struct TokenDetails {
        address tokenAddress;
        uint256 id;
        bool isERC1155;
    }

    address public override printer;

    constructor(address _printer) {
        printer = _printer;
    }

    //
    // ███████╗██████╗  ██████╗██████╗  ██████╗     ████████╗ ██████╗     ███████╗██████╗  ██████╗██████╗  ██████╗
    // ██╔════╝██╔══██╗██╔════╝╚════██╗██╔═████╗    ╚══██╔══╝██╔═══██╗    ██╔════╝██╔══██╗██╔════╝╚════██╗██╔═████╗
    // █████╗  ██████╔╝██║      █████╔╝██║██╔██║       ██║   ██║   ██║    █████╗  ██████╔╝██║      █████╔╝██║██╔██║
    // ██╔══╝  ██╔══██╗██║     ██╔═══╝ ████╔╝██║       ██║   ██║   ██║    ██╔══╝  ██╔══██╗██║     ██╔═══╝ ████╔╝██║
    // ███████╗██║  ██║╚██████╗███████╗╚██████╔╝       ██║   ╚██████╔╝    ███████╗██║  ██║╚██████╗███████╗╚██████╔╝
    // ╚══════╝╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝        ╚═╝    ╚═════╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝
    //

    function getERC20ToERC20AmountIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view override returns (uint256) {
        return
            _getMinAmountIn(
                IBook(IPrinter(printer).pairForERC20(tokenIn, tokenOut)),
                amountOut,
                _isERC20Token0(tokenOut, tokenIn) == true ? 0 : 1
            );
    }

    function getERC20ToERC20AmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256) {
        return
            _getMaxAmountOut(
                IBook(IPrinter(printer).pairForERC20(tokenIn, tokenOut)),
                amountIn,
                _isERC20Token0(tokenOut, tokenIn) == true ? 0 : 1
            );
    }

    function openERC20ToERC20Order(
        address _tokenIn,
        address _tokenOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external override returns (address book, uint256 orderId) {
        book = IPrinter(printer).pairForERC20(_tokenIn, _tokenOut);

        if (book == address(0)) {
            book = IPrinter(printer).createERC20Pair(_tokenIn, _tokenOut);
        }

        IERC20(_tokenIn).transferFrom(msg.sender, address(book), _amount);
        IBook(book).open(_price, _nextOrderIndex, msg.sender);

        orderId = _getOrderId(IBook(book).token0() == _tokenIn ? 0 : 1, _price);
    }

    function swapExactERC20forERC20(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountOut) {
        if (block.timestamp > deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).pairForERC20(tokenIn, tokenOut));
        bool tokenOutIsToken0 = tokenOut < tokenIn;
        amountOut = _getMaxAmountOut(book, amountIn, tokenOutIsToken0 ? 0 : 1);

        if (amountOut < amountOutMin) {
            revert AmountOutTooLow(amountOut);
        }

        IERC20(tokenIn).transferFrom(msg.sender, address(book), amountIn);
        book.swap(tokenOutIsToken0 ? amountOut : 0, tokenOutIsToken0 ? 0 : amountOut, to, '');
    }

    function swapERC20forExactERC20(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountIn) {
        if (block.timestamp > deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).pairForERC20(tokenIn, tokenOut));
        bool tokenOutIsToken0 = tokenOut < tokenIn;
        amountIn = _getMinAmountIn(book, amountOut, tokenOutIsToken0 ? 0 : 1);

        if (amountIn > amountInMax) {
            revert AmountInTooHigh(amountIn);
        }

        IERC20(tokenIn).transferFrom(msg.sender, address(book), amountIn);
        book.swap(tokenOutIsToken0 ? amountOut : 0, tokenOutIsToken0 ? 0 : amountOut, to, '');
    }

    //
    // ███████╗██████╗  ██████╗██████╗  ██████╗     ████████╗ ██████╗     ███████╗██████╗  ██████╗ ██╗ ██╗███████╗███████╗
    // ██╔════╝██╔══██╗██╔════╝╚════██╗██╔═████╗    ╚══██╔══╝██╔═══██╗    ██╔════╝██╔══██╗██╔════╝███║███║██╔════╝██╔════╝
    // █████╗  ██████╔╝██║      █████╔╝██║██╔██║       ██║   ██║   ██║    █████╗  ██████╔╝██║     ╚██║╚██║███████╗███████╗
    // ██╔══╝  ██╔══██╗██║     ██╔═══╝ ████╔╝██║       ██║   ██║   ██║    ██╔══╝  ██╔══██╗██║      ██║ ██║╚════██║╚════██║
    // ███████╗██║  ██║╚██████╗███████╗╚██████╔╝       ██║   ╚██████╔╝    ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║
    // ╚══════╝╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝        ╚═╝    ╚═════╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝
    //

    function getERC20ToERC1155AmountIn(
        address tokenIn,
        address tokenOut,
        uint256 idOut,
        uint256 amountOut
    ) external view override returns (uint256) {
        return _getMinAmountIn(IBook(IPrinter(printer).pairForHybrid(tokenOut, idOut, tokenIn)), amountOut, 0);
    }

    function getERC20ToERC1155AmountOut(
        address tokenIn,
        address tokenOut,
        uint256 idOut,
        uint256 amountIn
    ) external view override returns (uint256) {
        return _getMaxAmountOut(IBook(IPrinter(printer).pairForHybrid(tokenOut, idOut, tokenIn)), amountIn, 0);
    }

    function openERC20ToERC1155Order(
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external override returns (address book, uint256 orderId) {
        book = IPrinter(printer).pairForHybrid(_tokenOut, _idOut, _tokenIn);

        if (book == address(0)) {
            book = IPrinter(printer).createHybridPair(_tokenOut, _idOut, _tokenIn);
        }

        IERC20(_tokenIn).transferFrom(msg.sender, address(book), _amount);
        IBook(book).open(_price, _nextOrderIndex, msg.sender);

        orderId = _getOrderId(1, _price);
    }

    function swapExactERC20forERC1155(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        uint256 idOut,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountOut) {
        if (block.timestamp > deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).pairForHybrid(tokenOut, idOut, tokenIn));
        amountOut = _getMaxAmountOut(book, amountIn, 0);

        if (amountOut < amountOutMin) {
            revert AmountOutTooLow(amountOut);
        }

        IERC20(tokenIn).transferFrom(msg.sender, address(book), amountIn);
        book.swap(amountOut, 0, to, '');
    }

    function swapERC20forExactERC1155(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut,
        uint256 idOut,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountIn) {
        if (block.timestamp > deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).pairForHybrid(tokenOut, idOut, tokenIn));
        amountIn = _getMinAmountIn(book, amountOut, 0);

        if (amountIn > amountInMax) {
            revert AmountInTooHigh(amountIn);
        }

        IERC20(tokenIn).transferFrom(msg.sender, address(book), amountIn);
        book.swap(amountOut, 0, to, '');
    }

    //
    // ███████╗██████╗  ██████╗ ██╗ ██╗███████╗███████╗    ████████╗ ██████╗     ███████╗██████╗  ██████╗██████╗  ██████╗
    // ██╔════╝██╔══██╗██╔════╝███║███║██╔════╝██╔════╝    ╚══██╔══╝██╔═══██╗    ██╔════╝██╔══██╗██╔════╝╚════██╗██╔═████╗
    // █████╗  ██████╔╝██║     ╚██║╚██║███████╗███████╗       ██║   ██║   ██║    █████╗  ██████╔╝██║      █████╔╝██║██╔██║
    // ██╔══╝  ██╔══██╗██║      ██║ ██║╚════██║╚════██║       ██║   ██║   ██║    ██╔══╝  ██╔══██╗██║     ██╔═══╝ ████╔╝██║
    // ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║       ██║   ╚██████╔╝    ███████╗██║  ██║╚██████╗███████╗╚██████╔╝
    // ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝       ╚═╝    ╚═════╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝
    //

    function getERC155ToERC20AmountIn(
        address tokenIn,
        uint256 idIn,
        address tokenOut,
        uint256 amountOut
    ) external view override returns (uint256) {
        return _getMinAmountIn(IBook(IPrinter(printer).pairForHybrid(tokenIn, idIn, tokenOut)), amountOut, 1);
    }

    function getERC155ToERC20AmountOut(
        address tokenIn,
        uint256 idIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256) {
        return _getMaxAmountOut(IBook(IPrinter(printer).pairForHybrid(tokenIn, idIn, tokenOut)), amountIn, 1);
    }

    function openERC1155ToERC20Order(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external override returns (address book, uint256 orderId) {
        book = IPrinter(printer).pairForHybrid(_tokenIn, _idIn, _tokenOut);

        if (book == address(0)) {
            book = IPrinter(printer).createHybridPair(_tokenIn, _idIn, _tokenOut);
        }

        IERC1155(_tokenIn).safeTransferFrom(msg.sender, address(book), _idIn, _amount, '');
        IBook(book).open(_price, _nextOrderIndex, msg.sender);

        orderId = _getOrderId(0, _price);
    }

    function swapExactERC1155forERC20(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        uint256 idIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountOut) {
        if (block.timestamp > deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).pairForHybrid(tokenIn, idIn, tokenOut));
        amountOut = _getMaxAmountOut(book, amountIn, 1);

        if (amountOut < amountOutMin) {
            revert AmountOutTooLow(amountOut);
        }

        IERC1155(tokenIn).safeTransferFrom(msg.sender, address(book), idIn, amountIn, '');
        book.swap(0, amountOut, to, '');
    }

    function swapERC1155forExactERC20(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        uint256 idIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountIn) {
        if (block.timestamp > deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).pairForHybrid(tokenIn, idIn, tokenOut));
        amountIn = _getMinAmountIn(book, amountOut, 1);

        if (amountIn > amountInMax) {
            revert AmountInTooHigh(amountIn);
        }

        IERC1155(tokenIn).safeTransferFrom(msg.sender, address(book), idIn, amountIn, '');
        book.swap(0, amountOut, to, '');
    }

    //
    // ███████╗██████╗  ██████╗ ██╗ ██╗███████╗███████╗    ████████╗ ██████╗     ███████╗██████╗  ██████╗ ██╗ ██╗███████╗███████╗
    // ██╔════╝██╔══██╗██╔════╝███║███║██╔════╝██╔════╝    ╚══██╔══╝██╔═══██╗    ██╔════╝██╔══██╗██╔════╝███║███║██╔════╝██╔════╝
    // █████╗  ██████╔╝██║     ╚██║╚██║███████╗███████╗       ██║   ██║   ██║    █████╗  ██████╔╝██║     ╚██║╚██║███████╗███████╗
    // ██╔══╝  ██╔══██╗██║      ██║ ██║╚════██║╚════██║       ██║   ██║   ██║    ██╔══╝  ██╔══██╗██║      ██║ ██║╚════██║╚════██║
    // ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║       ██║   ╚██████╔╝    ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║
    // ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝       ╚═╝    ╚═════╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝
    //

    function getERC155ToERC1155AmountIn(
        address tokenIn,
        uint256 idIn,
        address tokenOut,
        uint256 idOut,
        uint256 amountOut
    ) external view override returns (uint256) {
        return
            _getMinAmountIn(
                IBook(IPrinter(printer).pairForERC1155(tokenIn, idIn, tokenOut, idOut)),
                amountOut,
                _isERC1155Token0(tokenOut, idOut, tokenIn, idIn) == true ? 0 : 1
            );
    }

    function getERC155ToERC1155AmountOut(
        address tokenIn,
        uint256 idIn,
        address tokenOut,
        uint256 idOut,
        uint256 amountIn
    ) external view override returns (uint256) {
        return
            _getMaxAmountOut(
                IBook(IPrinter(printer).pairForERC1155(tokenIn, idIn, tokenOut, idOut)),
                amountIn,
                _isERC1155Token0(tokenOut, idOut, tokenIn, idIn) == true ? 0 : 1
            );
    }

    function openERC1155ToERC1155Order(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external override returns (address book, uint256 orderId) {
        book = IPrinter(printer).pairForERC1155(_tokenIn, _idIn, _tokenOut, _idOut);

        if (book == address(0)) {
            book = IPrinter(printer).createERC1155Pair(_tokenIn, _idIn, _tokenOut, _idOut);
        }

        IERC1155(_tokenIn).safeTransferFrom(msg.sender, address(book), _idIn, _amount, '');
        IBook(book).open(_price, _nextOrderIndex, msg.sender);

        if (_tokenIn != _tokenOut) {
            orderId = _getOrderId(IBook(book).id0() == _idIn ? 0 : 1, _price);
        } else {
            orderId = _getOrderId(IBook(book).token0() == _tokenIn ? 0 : 1, _price);
        }
    }

    function swapExactERC1155forERC1155(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        uint256 idIn,
        address tokenOut,
        uint256 idOut,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountOut) {
        if (block.timestamp > deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).pairForERC1155(tokenIn, idIn, tokenOut, idOut));
        bool tokenOutIsToken0 = tokenOut == tokenIn ? idOut < idIn : tokenOut < tokenIn;
        amountOut = _getMaxAmountOut(book, amountIn, tokenOutIsToken0 ? 0 : 1);

        if (amountOut < amountOutMin) {
            revert AmountOutTooLow(amountOut);
        }

        IERC1155(tokenIn).safeTransferFrom(msg.sender, address(book), idIn, amountIn, '');
        book.swap(tokenOutIsToken0 ? amountOut : 0, tokenOutIsToken0 ? 0 : amountOut, to, '');
    }

    function swapERC1155forExactERC1155(
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        uint256 idIn,
        address tokenOut,
        uint256 idOut,
        address to,
        uint256 deadline
    ) external override returns (uint256 amountIn) {
        if (block.timestamp > deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).pairForERC1155(tokenIn, idIn, tokenOut, idOut));
        bool tokenOutIsToken0 = tokenOut == tokenIn ? idOut < idIn : tokenOut < tokenIn;
        amountIn = _getMinAmountIn(book, amountOut, tokenOutIsToken0 ? 0 : 1);

        if (amountIn > amountInMax) {
            revert AmountInTooHigh(amountIn);
        }

        IERC1155(tokenIn).safeTransferFrom(msg.sender, address(book), idIn, amountIn, '');
        book.swap(tokenOutIsToken0 ? amountOut : 0, tokenOutIsToken0 ? 0 : amountOut, to, '');
    }

    //
    // ███╗   ███╗██╗   ██╗██╗  ████████╗██╗    ███████╗████████╗███████╗██████╗ ███████╗
    // ████╗ ████║██║   ██║██║  ╚══██╔══╝██║    ██╔════╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝
    // ██╔████╔██║██║   ██║██║     ██║   ██║    ███████╗   ██║   █████╗  ██████╔╝███████╗
    // ██║╚██╔╝██║██║   ██║██║     ██║   ██║    ╚════██║   ██║   ██╔══╝  ██╔═══╝ ╚════██║
    // ██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║    ███████║   ██║   ███████╗██║     ███████║
    // ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝    ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚══════╝
    //

    function getAmountsOut(uint256[] calldata path, uint256 amountIn)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        TokenDetails[] memory td = _pathToTokenDetails(path);
        return _getAmountsOut(td, amountIn);
    }

    function getAmountsIn(uint256[] calldata path, uint256 amountOut)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        TokenDetails[] memory td = _pathToTokenDetails(path);
        return _getAmountsIn(td, amountOut);
    }

    function swapExactInPath(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        if (block.timestamp > deadline) {
            revert DeadlineCrossed();
        }

        if (path.length < 2) {
            revert InvalidArrayLength();
        }

        TokenDetails[] memory tokenDetails = _pathToTokenDetails(path);
        amounts = _getAmountsOut(tokenDetails, amountIn);

        if (amounts[amounts.length - 1] < amountOutMin) {
            revert AmountOutTooLow(amounts[amounts.length - 1]);
        }

        _executeSwapPath(tokenDetails, amounts, to);
    }

    function swapExactOutPath(
        uint256 amountOut,
        uint256 amountInMax,
        uint256[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        if (block.timestamp > deadline) {
            revert DeadlineCrossed();
        }

        if (path.length < 2) {
            revert InvalidArrayLength();
        }

        TokenDetails[] memory tokenDetails = _pathToTokenDetails(path);
        amounts = _getAmountsIn(tokenDetails, amountOut);

        if (amounts[0] > amountInMax) {
            revert AmountInTooHigh(amounts[0]);
        }

        _executeSwapPath(tokenDetails, amounts, to);
    }

    //
    //  ██████╗ ██████╗ ███╗   ███╗███╗   ███╗ ██████╗ ███╗   ██╗
    // ██╔════╝██╔═══██╗████╗ ████║████╗ ████║██╔═══██╗████╗  ██║
    // ██║     ██║   ██║██╔████╔██║██╔████╔██║██║   ██║██╔██╗ ██║
    // ██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██║   ██║██║╚██╗██║
    // ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║╚██████╔╝██║ ╚████║
    //  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝
    //

    function closeOrder(
        address _book,
        uint256 _id,
        uint256 _amount
    ) external override {
        IERC1155(_book).safeTransferFrom(msg.sender, address(_book), _id, _amount, '');
        IBook(_book).close(_id, msg.sender);
    }

    function settle(
        address[] calldata books,
        uint256[][] calldata orderIds,
        address _owner
    ) external override {
        if (books.length != orderIds.length || books.length == 0) {
            revert InvalidArrayLength();
        }

        for (uint256 i; i < books.length; ) {
            IBook(books[i]).settle(_owner, orderIds[i]);
            unchecked {
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

    function _getOrderId(uint8 _token, uint256 _price) internal pure returns (uint256 id) {
        id = _price << 1;
        if (_token == 1) {
            id += 1;
        }
        id = id << 1;
    }

    function _getAmountIn(
        uint256 amountOut,
        uint256 price,
        uint8 decimalSum
    ) internal pure returns (uint256) {
        return ((amountOut * (10**decimalSum)) / price);
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 price,
        uint8 decimalSum
    ) internal pure returns (uint256) {
        return (amountIn * price) / 10**decimalSum;
    }

    function _getMaxAmountOut(
        IBook book,
        uint256 amountIn,
        uint8 tokenOut
    ) internal view returns (uint256 amountOut) {
        IBook.Order memory order = tokenOut == 0 ? book.head0() : book.head1();
        uint8 decimalSum = book.decimals0() + book.decimals1();
        while (amountIn > 0) {
            uint256 maxAmountIn = _getAmountIn(order.remainingLiquidity + order.nextLiquidity, order.price, decimalSum);
            if (maxAmountIn > amountIn) {
                amountIn = 0;
                amountOut += _getAmountOut(amountIn, order.price, decimalSum);
            } else {
                amountIn -= maxAmountIn;
                amountOut += _getAmountOut(maxAmountIn, order.price, decimalSum);
                if (order.next == 0) {
                    revert InsufficientLiquidity(address(book), tokenOut, amountOut);
                }
                order = book.orders(order.next);
            }
        }
    }

    function _getMinAmountIn(
        IBook book,
        uint256 amountOut,
        uint8 tokenOut
    ) internal view returns (uint256 amountIn) {
        IBook.Order memory order = tokenOut == 0 ? book.head0() : book.head1();
        uint8 decimalSum = book.decimals0() + book.decimals1();
        while (amountOut > 0) {
            uint256 maxAmountOut = _getAmountOut(
                order.remainingLiquidity + order.nextLiquidity,
                order.price,
                decimalSum
            );
            if (maxAmountOut > amountOut) {
                amountOut = 0;
                amountIn += _getAmountIn(amountOut, order.price, decimalSum);
            } else {
                amountOut -= maxAmountOut;
                amountIn += _getAmountIn(maxAmountOut, order.price, decimalSum);
                if (order.next == 0) {
                    revert InsufficientLiquidity(address(book), tokenOut, amountOut);
                }
                order = book.orders(order.next);
            }
        }
    }

    function _isERC20Token0(address tokenA, address tokenB) internal pure returns (bool) {
        return tokenA < tokenB;
    }

    function _isERC1155Token0(
        address tokenA,
        uint256 idA,
        address tokenB,
        uint256 idB
    ) internal pure returns (bool) {
        if (tokenA == tokenB) {
            return idA < idB;
        }
        return tokenA < tokenB;
    }

    function _getAmountsOut(TokenDetails[] memory path, uint256 amountIn)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);

        for (uint256 i; i < path.length - 1; ) {
            amounts[i] = amountIn;
            if (path[i].isERC1155 == false && path[i + 1].isERC1155 == false) {
                amountIn = _getMaxAmountOut(
                    IBook(IPrinter(printer).pairForERC20(path[i].tokenAddress, path[i + 1].tokenAddress)),
                    amountIn,
                    _isERC20Token0(path[i].tokenAddress, path[i + 1].tokenAddress) == true ? 1 : 0
                );
            } else if (path[i].isERC1155 == true && path[i + 1].isERC1155 == true) {
                amountIn = _getMaxAmountOut(
                    IBook(
                        IPrinter(printer).pairForERC1155(
                            path[i].tokenAddress,
                            path[i].id,
                            path[i + 1].tokenAddress,
                            path[i + 1].id
                        )
                    ),
                    amountIn,
                    _isERC1155Token0(path[i].tokenAddress, path[i].id, path[i + 1].tokenAddress, path[i + 1].id) == true
                        ? 1
                        : 0
                );
            } else if (path[i].isERC1155 == true && path[i + 1].isERC1155 == false) {
                amountIn = _getMaxAmountOut(
                    IBook(IPrinter(printer).pairForHybrid(path[i].tokenAddress, path[i].id, path[i + 1].tokenAddress)),
                    amountIn,
                    1
                );
            } else if (path[i].isERC1155 == false && path[i + 1].isERC1155 == true) {
                amountIn = _getMaxAmountOut(
                    IBook(
                        IPrinter(printer).pairForHybrid(path[i + 1].tokenAddress, path[i + 1].id, path[i].tokenAddress)
                    ),
                    amountIn,
                    0
                );
            }

            unchecked {
                ++i;
            }
        }

        amounts[path.length - 1] = amountIn;
    }

    function _getAmountsIn(TokenDetails[] memory path, uint256 amountOut)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);

        for (uint256 i = path.length - 1; i > 1; ) {
            amounts[i] = amountOut;
            if (path[i].isERC1155 == false && path[i - 1].isERC1155 == false) {
                amountOut = _getMinAmountIn(
                    IBook(IPrinter(printer).pairForERC20(path[i].tokenAddress, path[i + 1].tokenAddress)),
                    amountOut,
                    _isERC20Token0(path[i].tokenAddress, path[i - 1].tokenAddress) == true ? 0 : 1
                );
            } else if (path[i].isERC1155 == true && path[i - 1].isERC1155 == true) {
                amountOut = _getMinAmountIn(
                    IBook(
                        IPrinter(printer).pairForERC1155(
                            path[i].tokenAddress,
                            path[i].id,
                            path[i - 1].tokenAddress,
                            path[i - 1].id
                        )
                    ),
                    amountOut,
                    _isERC1155Token0(path[i].tokenAddress, path[i].id, path[i - 1].tokenAddress, path[i - 1].id) == true
                        ? 1
                        : 0
                );
            } else if (path[i].isERC1155 == true && path[i - 1].isERC1155 == false) {
                amountOut = _getMinAmountIn(
                    IBook(IPrinter(printer).pairForHybrid(path[i].tokenAddress, path[i].id, path[i - 1].tokenAddress)),
                    amountOut,
                    0
                );
            } else if (path[i].isERC1155 == false && path[i - 1].isERC1155 == true) {
                amountOut = _getMinAmountIn(
                    IBook(
                        IPrinter(printer).pairForHybrid(path[i - 1].tokenAddress, path[i - 1].id, path[i].tokenAddress)
                    ),
                    amountOut,
                    1
                );
            }
            unchecked {
                ++i;
            }
        }

        amounts[0] = amountOut;
    }

    error InvalidPathArgument();

    function _pathToTokenDetails(uint256[] calldata path) internal pure returns (TokenDetails[] memory tokenDetails) {
        uint256 count;
        for (uint256 i; i < path.length; ) {
            if (path[i] & 1 == 1) {
                // erc1155
                ++i;
            }

            ++count;

            unchecked {
                ++i;
            }
        }
        tokenDetails = new TokenDetails[](count);
        count = 0;

        for (uint256 i; i < path.length; ) {
            if (path[i] & 1 == 1) {
                // erc1155

                if (i + 1 == path.length) {
                    revert InvalidPathArgument();
                }

                tokenDetails[count] = TokenDetails({
                    tokenAddress: address(uint160(path[i] >> 1)),
                    id: path[i + 1],
                    isERC1155: true
                });

                ++i;
            } else {
                tokenDetails[count] = TokenDetails({
                    tokenAddress: address(uint160(path[i] >> 1)),
                    id: 0,
                    isERC1155: false
                });
            }

            ++count;

            unchecked {
                ++i;
            }
        }
    }

    function _getAddress(TokenDetails memory tokenIn, TokenDetails memory tokenOut) internal view returns (address) {
        if (tokenIn.isERC1155 != tokenOut.isERC1155) {
            if (tokenIn.isERC1155 == true) {
                return IPrinter(printer).pairForHybrid(tokenIn.tokenAddress, tokenIn.id, tokenOut.tokenAddress);
            } else {
                return IPrinter(printer).pairForHybrid(tokenOut.tokenAddress, tokenOut.id, tokenIn.tokenAddress);
            }
        } else {
            if (tokenIn.isERC1155 == true) {
                return
                    IPrinter(printer).pairForERC1155(
                        tokenIn.tokenAddress,
                        tokenIn.id,
                        tokenOut.tokenAddress,
                        tokenOut.id
                    );
            } else {
                return IPrinter(printer).pairForERC20(tokenIn.tokenAddress, tokenOut.tokenAddress);
            }
        }
    }

    function _executeSwap(
        IBook book,
        TokenDetails memory tokenIn,
        TokenDetails memory tokenOut,
        uint256 amountOut,
        address recipient
    ) internal {
        if (tokenIn.isERC1155 != tokenOut.isERC1155) {
            if (tokenIn.isERC1155 == true) {
                // in is token0
                book.swap(0, amountOut, recipient, '');
            } else {
                // out is token0
                book.swap(amountOut, 0, recipient, '');
            }
        } else {
            if (tokenIn.isERC1155 == true) {
                // both are 1155

                if (book.token0() == tokenIn.tokenAddress && book.id0() == tokenIn.id) {
                    // in is token0
                    book.swap(0, amountOut, recipient, '');
                } else {
                    // out is token0
                    book.swap(amountOut, 0, recipient, '');
                }
            } else {
                // both are 20

                if (book.token0() == tokenIn.tokenAddress) {
                    // in is token0
                    book.swap(0, amountOut, recipient, '');
                } else {
                    // out is token0
                    book.swap(amountOut, 0, recipient, '');
                }
            }
        }
    }

    function _transfer(
        TokenDetails memory token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (token.isERC1155) {
            IERC1155(token.tokenAddress).safeTransferFrom(from, to, token.id, amount, '');
        } else {
            IERC20(token.tokenAddress).transferFrom(from, to, amount);
        }
    }

    function _executeSwapPath(
        TokenDetails[] memory tokenDetails,
        uint256[] memory amounts,
        address to
    ) internal {
        address currentAddress = _getAddress(tokenDetails[0], tokenDetails[1]);
        address recipientAddress;

        _transfer(tokenDetails[0], msg.sender, currentAddress, amounts[0]);

        for (uint256 i; i < tokenDetails.length - 1; ) {
            if (i + 1 == tokenDetails.length - 1) {
                recipientAddress = to;
            } else {
                recipientAddress = _getAddress(tokenDetails[i + 1], tokenDetails[i + 2]);
            }

            _executeSwap(IBook(currentAddress), tokenDetails[i], tokenDetails[i + 1], amounts[i + 1], recipientAddress);

            currentAddress = recipientAddress;

            unchecked {
                ++i;
            }
        }
    }
}
