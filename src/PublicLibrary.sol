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

    //
    // ███████╗██████╗  ██████╗██████╗  ██████╗     ████████╗ ██████╗     ███████╗██████╗  ██████╗██████╗  ██████╗
    // ██╔════╝██╔══██╗██╔════╝╚════██╗██╔═████╗    ╚══██╔══╝██╔═══██╗    ██╔════╝██╔══██╗██╔════╝╚════██╗██╔═████╗
    // █████╗  ██████╔╝██║      █████╔╝██║██╔██║       ██║   ██║   ██║    █████╗  ██████╔╝██║      █████╔╝██║██╔██║
    // ██╔══╝  ██╔══██╗██║     ██╔═══╝ ████╔╝██║       ██║   ██║   ██║    ██╔══╝  ██╔══██╗██║     ██╔═══╝ ████╔╝██║
    // ███████╗██║  ██║╚██████╗███████╗╚██████╔╝       ██║   ╚██████╔╝    ███████╗██║  ██║╚██████╗███████╗╚██████╔╝
    // ╚══════╝╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝        ╚═╝    ╚═════╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝
    //

    /// @notice Get amount of input token to provide for a target output amount between two ERC20 tokens
    /// @param _tokenIn Address of input token
    /// @param _tokenOut Address of output token
    /// @param _amountOut Target amount out
    function getERC20ToERC20AmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) external view override returns (uint256) {
        return
            _getMinAmountIn(
                IBook(IPrinter(printer).bookForERC20(_tokenIn, _tokenOut)),
                _amountOut,
                _isERC20Token0(_tokenOut, _tokenIn) == true ? 0 : 1
            );
    }

    /// @notice Get amount of output token to provide for a target input amount between two ERC20 tokens
    /// @param _tokenIn Address of input token
    /// @param _tokenOut Address of output token
    /// @param _amountIn Target amount in
    function getERC20ToERC20AmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view override returns (uint256) {
        return
            _getMaxAmountOut(
                IBook(IPrinter(printer).bookForERC20(_tokenIn, _tokenOut)),
                _amountIn,
                _isERC20Token0(_tokenOut, _tokenIn) == true ? 0 : 1
            );
    }

    /// @notice Open order on _tokenOut of _amount tokens at price _price
    /// @param _tokenIn Address of input token
    /// @param _tokenOut Address of output token
    /// @param _price Order price, interpreted as amount of _tokenOut to receive per _tokenIn
    /// @param _amount Order size
    /// @param _nextOrderIndex Index of the next order in the target Book
    function openERC20ToERC20Order(
        address _tokenIn,
        address _tokenOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external override returns (address book, uint256 orderId) {
        book = IPrinter(printer).bookForERC20(_tokenIn, _tokenOut);

        if (book == address(0)) {
            book = IPrinter(printer).createERC20Book(_tokenIn, _tokenOut);
        }

        IERC20(_tokenOut).transferFrom(msg.sender, address(book), _amount);
        IBook(book).open(_price, _nextOrderIndex, msg.sender);

        orderId = _getOrderId(IBook(book).token0() == _tokenIn ? 1 : 0, _price);
    }

    /// @notice Swap exact input token amount of output token
    /// @param _amountIn Exact input amount
    /// @param _amountOutMin Minimal accepted output amount
    /// @param _tokenIn Address of input token
    /// @param _tokenOut Address of output token
    /// @param _to Swap output recipient
    /// @param _deadline Timestamp after which swap is invalid
    function swapExactERC20forERC20(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _tokenIn,
        address _tokenOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountOut) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).bookForERC20(_tokenIn, _tokenOut));
        bool tokenOutIsToken0 = _tokenOut < _tokenIn;
        amountOut = _getMaxAmountOut(book, _amountIn, tokenOutIsToken0 ? 0 : 1);

        if (amountOut < _amountOutMin) {
            revert AmountOutTooLow(amountOut);
        }

        IERC20(_tokenIn).transferFrom(msg.sender, address(book), _amountIn);
        book.swap(tokenOutIsToken0 ? amountOut : 0, tokenOutIsToken0 ? 0 : amountOut, _to, '');
    }

    /// @notice Swap input token for exact output token
    /// @param _amountOut Exact output amount
    /// @param _amountInMax Maximal accepted input amount
    /// @param _tokenIn Address of input token
    /// @param _tokenOut Address of output token
    /// @param _to Swap output recipient
    /// @param _deadline Timestamp after which swap is invalid
    function swapERC20forExactERC20(
        uint256 _amountOut,
        uint256 _amountInMax,
        address _tokenIn,
        address _tokenOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountIn) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).bookForERC20(_tokenIn, _tokenOut));
        bool tokenOutIsToken0 = _tokenOut < _tokenIn;
        amountIn = _getMinAmountIn(book, _amountOut, tokenOutIsToken0 ? 0 : 1);

        if (amountIn > _amountInMax) {
            revert AmountInTooHigh(amountIn);
        }

        IERC20(_tokenIn).transferFrom(msg.sender, address(book), amountIn);
        book.swap(tokenOutIsToken0 ? _amountOut : 0, tokenOutIsToken0 ? 0 : _amountOut, _to, '');
    }

    //
    // ███████╗██████╗  ██████╗██████╗  ██████╗     ████████╗ ██████╗     ███████╗██████╗  ██████╗ ██╗ ██╗███████╗███████╗
    // ██╔════╝██╔══██╗██╔════╝╚════██╗██╔═████╗    ╚══██╔══╝██╔═══██╗    ██╔════╝██╔══██╗██╔════╝███║███║██╔════╝██╔════╝
    // █████╗  ██████╔╝██║      █████╔╝██║██╔██║       ██║   ██║   ██║    █████╗  ██████╔╝██║     ╚██║╚██║███████╗███████╗
    // ██╔══╝  ██╔══██╗██║     ██╔═══╝ ████╔╝██║       ██║   ██║   ██║    ██╔══╝  ██╔══██╗██║      ██║ ██║╚════██║╚════██║
    // ███████╗██║  ██║╚██████╗███████╗╚██████╔╝       ██║   ╚██████╔╝    ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║
    // ╚══════╝╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝        ╚═╝    ╚═════╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝
    //

    /// @notice Get amount of input token to provide for a target output amount for ERC20 to ERC1155 trade
    /// @param _tokenIn Address of input token
    /// @param _tokenOut Address of output token
    /// @param _idOut ERC1155 output token id
    /// @param _amountOut Target amount out
    function getERC20ToERC1155AmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _amountOut
    ) external view override returns (uint256) {
        return _getMinAmountIn(IBook(IPrinter(printer).bookForHybrid(_tokenOut, _idOut, _tokenIn)), _amountOut, 0);
    }

    /// @notice Get amount of output token to provide for a target input amount for ERC20 to ERC1155 trade
    /// @param _tokenIn Address of input token
    /// @param _tokenOut Address of output token
    /// @param _idOut ERC1155 output token id
    /// @param _amountIn Target amount in
    function getERC20ToERC1155AmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _amountIn
    ) external view override returns (uint256) {
        return _getMaxAmountOut(IBook(IPrinter(printer).bookForHybrid(_tokenOut, _idOut, _tokenIn)), _amountIn, 0);
    }

    /// @notice Open order on _tokenOut+_idOut of _amount tokens at price _price
    /// @param _tokenIn Address of input token
    /// @param _tokenOut Address of output token
    /// @param _idOut ERC1155 output token id
    /// @param _price Order price, interpreted as amount of _tokenOut to receive per _tokenIn
    /// @param _amount Order size
    /// @param _nextOrderIndex Index of the next order in the target Book
    function openERC20ToERC1155Order(
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external override returns (address book, uint256 orderId) {
        book = IPrinter(printer).bookForHybrid(_tokenOut, _idOut, _tokenIn);

        if (book == address(0)) {
            book = IPrinter(printer).createHybridBook(_tokenOut, _idOut, _tokenIn);
        }

        IERC20(_tokenIn).transferFrom(msg.sender, address(book), _amount);
        IBook(book).open(_price, _nextOrderIndex, msg.sender);

        orderId = _getOrderId(1, _price);
    }

    /// @notice Swap exact input token amount of output token
    /// @param _amountIn Exact input amount
    /// @param _amountOutMin Minimal accepted output amount
    /// @param _tokenIn Address of input token
    /// @param _tokenOut Address of output token
    /// @param _idOut ERC1155 output token id
    /// @param _to Swap output recipient
    /// @param _deadline Timestamp after which swap is invalid
    function swapExactERC20forERC1155(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountOut) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).bookForHybrid(_tokenOut, _idOut, _tokenIn));
        amountOut = _getMaxAmountOut(book, _amountIn, 0);

        if (amountOut < _amountOutMin) {
            revert AmountOutTooLow(amountOut);
        }

        IERC20(_tokenIn).transferFrom(msg.sender, address(book), _amountIn);
        book.swap(amountOut, 0, _to, '');
    }

    /// @notice Swap input token for exact output token
    /// @param _amountOut Exact output amount
    /// @param _amountInMax Maximal accepted input amount
    /// @param _tokenIn Address of input token
    /// @param _tokenOut Address of output token
    /// @param _idOut ERC1155 output token id
    /// @param _to Swap output recipient
    /// @param _deadline Timestamp after which swap is invalid
    function swapERC20forExactERC1155(
        uint256 _amountOut,
        uint256 _amountInMax,
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountIn) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).bookForHybrid(_tokenOut, _idOut, _tokenIn));
        amountIn = _getMinAmountIn(book, _amountOut, 0);

        if (amountIn > _amountInMax) {
            revert AmountInTooHigh(amountIn);
        }

        IERC20(_tokenIn).transferFrom(msg.sender, address(book), amountIn);
        book.swap(_amountOut, 0, _to, '');
    }

    //
    // ███████╗██████╗  ██████╗ ██╗ ██╗███████╗███████╗    ████████╗ ██████╗     ███████╗██████╗  ██████╗██████╗  ██████╗
    // ██╔════╝██╔══██╗██╔════╝███║███║██╔════╝██╔════╝    ╚══██╔══╝██╔═══██╗    ██╔════╝██╔══██╗██╔════╝╚════██╗██╔═████╗
    // █████╗  ██████╔╝██║     ╚██║╚██║███████╗███████╗       ██║   ██║   ██║    █████╗  ██████╔╝██║      █████╔╝██║██╔██║
    // ██╔══╝  ██╔══██╗██║      ██║ ██║╚════██║╚════██║       ██║   ██║   ██║    ██╔══╝  ██╔══██╗██║     ██╔═══╝ ████╔╝██║
    // ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║       ██║   ╚██████╔╝    ███████╗██║  ██║╚██████╗███████╗╚██████╔╝
    // ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝       ╚═╝    ╚═════╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝╚══════╝ ╚═════╝
    //

    /// @notice Get amount of input token to provide for a target output amount for ERC1155 to ERC20 trade
    /// @param _tokenIn Address of input token
    /// @param _idIn ERC1155 input token id
    /// @param _tokenOut Address of output token
    /// @param _amountOut Target amount out
    function getERC155ToERC20AmountIn(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _amountOut
    ) external view override returns (uint256) {
        return _getMinAmountIn(IBook(IPrinter(printer).bookForHybrid(_tokenIn, _idIn, _tokenOut)), _amountOut, 1);
    }

    /// @notice Get amount of output token to provide for a target input amount for ERC1155 to ERC20 trade
    /// @param _tokenIn Address of input token
    /// @param _idIn ERC1155 input token id
    /// @param _tokenOut Address of output token
    /// @param _amountIn Target amount in
    function getERC155ToERC20AmountOut(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view override returns (uint256) {
        return _getMaxAmountOut(IBook(IPrinter(printer).bookForHybrid(_tokenIn, _idIn, _tokenOut)), _amountIn, 1);
    }

    /// @notice Open order on _tokenOut+_idOut of _amount tokens at price _price
    /// @param _tokenIn Address of input token
    /// @param _idIn ERC1155 input token id
    /// @param _tokenOut Address of output token
    /// @param _price Order price, interpreted as amount of _tokenOut to receive per _tokenIn
    /// @param _amount Order size
    /// @param _nextOrderIndex Index of the next order in the target Book
    function openERC1155ToERC20Order(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external override returns (address book, uint256 orderId) {
        book = IPrinter(printer).bookForHybrid(_tokenIn, _idIn, _tokenOut);

        if (book == address(0)) {
            book = IPrinter(printer).createHybridBook(_tokenIn, _idIn, _tokenOut);
        }

        IERC1155(_tokenIn).safeTransferFrom(msg.sender, address(book), _idIn, _amount, '');
        IBook(book).open(_price, _nextOrderIndex, msg.sender);

        orderId = _getOrderId(0, _price);
    }

    /// @notice Swap exact input token amount of output token
    /// @param _amountIn Exact input amount
    /// @param _amountOutMin Minimal accepted output amount
    /// @param _tokenIn Address of input token
    /// @param _idIn ERC1155 input token id
    /// @param _tokenOut Address of output token
    /// @param _to Swap output recipient
    /// @param _deadline Timestamp after which swap is invalid
    function swapExactERC1155forERC20(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountOut) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).bookForHybrid(_tokenIn, _idIn, _tokenOut));
        amountOut = _getMaxAmountOut(book, _amountIn, 1);

        if (amountOut < _amountOutMin) {
            revert AmountOutTooLow(amountOut);
        }

        IERC1155(_tokenIn).safeTransferFrom(msg.sender, address(book), _idIn, _amountIn, '');
        book.swap(0, amountOut, _to, '');
    }

    /// @notice Swap input token for exact output token
    /// @param _amountOut Exact output amount
    /// @param _amountInMax Maximal accepted input amount
    /// @param _tokenIn Address of input token
    /// @param _idIn ERC1155 input token id
    /// @param _tokenOut Address of output token
    /// @param _to Swap output recipient
    /// @param _deadline Timestamp after which swap is invalid
    function swapERC1155forExactERC20(
        uint256 _amountOut,
        uint256 _amountInMax,
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountIn) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).bookForHybrid(_tokenIn, _idIn, _tokenOut));
        amountIn = _getMinAmountIn(book, _amountOut, 1);

        if (amountIn > _amountInMax) {
            revert AmountInTooHigh(amountIn);
        }

        IERC1155(_tokenIn).safeTransferFrom(msg.sender, address(book), _idIn, amountIn, '');
        book.swap(0, _amountOut, _to, '');
    }

    //
    // ███████╗██████╗  ██████╗ ██╗ ██╗███████╗███████╗    ████████╗ ██████╗     ███████╗██████╗  ██████╗ ██╗ ██╗███████╗███████╗
    // ██╔════╝██╔══██╗██╔════╝███║███║██╔════╝██╔════╝    ╚══██╔══╝██╔═══██╗    ██╔════╝██╔══██╗██╔════╝███║███║██╔════╝██╔════╝
    // █████╗  ██████╔╝██║     ╚██║╚██║███████╗███████╗       ██║   ██║   ██║    █████╗  ██████╔╝██║     ╚██║╚██║███████╗███████╗
    // ██╔══╝  ██╔══██╗██║      ██║ ██║╚════██║╚════██║       ██║   ██║   ██║    ██╔══╝  ██╔══██╗██║      ██║ ██║╚════██║╚════██║
    // ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║       ██║   ╚██████╔╝    ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║
    // ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝       ╚═╝    ╚═════╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝
    //

    /// @notice Get amount of input token to provide for a target output amount between two ERC1155 tokens
    /// @param _tokenIn Address of input token
    /// @param _idIn ERC1155 input token id
    /// @param _tokenOut Address of output token
    /// @param _idOut ERC1155 output token id
    /// @param _amountOut Target amount out
    function getERC155ToERC1155AmountIn(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _amountOut
    ) external view override returns (uint256) {
        return
            _getMinAmountIn(
                IBook(IPrinter(printer).bookForERC1155(_tokenIn, _idIn, _tokenOut, _idOut)),
                _amountOut,
                _isERC1155Token0(_tokenOut, _idOut, _tokenIn, _idIn) == true ? 0 : 1
            );
    }

    /// @notice Get amount of output token to provide for a target input amount for between two ERC1155 tokens
    /// @param _tokenIn Address of input token
    /// @param _idIn ERC1155 input token id
    /// @param _tokenOut Address of output token
    /// @param _idOut ERC1155 output token id
    /// @param _amountIn Target amount in
    function getERC155ToERC1155AmountOut(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _amountIn
    ) external view override returns (uint256) {
        return
            _getMaxAmountOut(
                IBook(IPrinter(printer).bookForERC1155(_tokenIn, _idIn, _tokenOut, _idOut)),
                _amountIn,
                _isERC1155Token0(_tokenOut, _idOut, _tokenIn, _idIn) == true ? 0 : 1
            );
    }

    /// @notice Open order on _tokenOut+_idOut of _amount tokens at price _price
    /// @param _tokenIn Address of input token
    /// @param _idIn ERC1155 input token id
    /// @param _tokenOut Address of output token
    /// @param _idOut ERC1155 output token id
    /// @param _price Order price, interpreted as amount of _tokenOut to receive per _tokenIn
    /// @param _amount Order size
    /// @param _nextOrderIndex Index of the next order in the target Book
    function openERC1155ToERC1155Order(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external override returns (address book, uint256 orderId) {
        book = IPrinter(printer).bookForERC1155(_tokenIn, _idIn, _tokenOut, _idOut);

        if (book == address(0)) {
            book = IPrinter(printer).createERC1155Book(_tokenIn, _idIn, _tokenOut, _idOut);
        }

        IERC1155(_tokenIn).safeTransferFrom(msg.sender, address(book), _idIn, _amount, '');
        IBook(book).open(_price, _nextOrderIndex, msg.sender);

        if (_tokenIn != _tokenOut) {
            orderId = _getOrderId(IBook(book).id0() == _idIn ? 0 : 1, _price);
        } else {
            orderId = _getOrderId(IBook(book).token0() == _tokenIn ? 0 : 1, _price);
        }
    }

    /// @notice Swap exact input token amount of output token
    /// @param _amountIn Exact input amount
    /// @param _amountOutMin Minimal accepted output amount
    /// @param _tokenIn Address of input token
    /// @param _idIn ERC1155 input token id
    /// @param _tokenOut Address of output token
    /// @param _idOut ERC1155 output token id
    /// @param _to Swap output recipient
    /// @param _deadline Timestamp after which swap is invalid
    function swapExactERC1155forERC1155(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountOut) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).bookForERC1155(_tokenIn, _idIn, _tokenOut, _idOut));
        bool tokenOutIsToken0 = _tokenOut == _tokenIn ? _idOut < _idIn : _tokenOut < _tokenIn;
        amountOut = _getMaxAmountOut(book, _amountIn, tokenOutIsToken0 ? 0 : 1);

        if (amountOut < _amountOutMin) {
            revert AmountOutTooLow(amountOut);
        }

        IERC1155(_tokenIn).safeTransferFrom(msg.sender, address(book), _idIn, _amountIn, '');
        book.swap(tokenOutIsToken0 ? amountOut : 0, tokenOutIsToken0 ? 0 : amountOut, _to, '');
    }

    /// @notice Swap input token for exact output token
    /// @param _amountOut Exact output amount
    /// @param _amountInMax Maximal accepted input amount
    /// @param _tokenIn Address of input token
    /// @param _idIn ERC1155 input token id
    /// @param _tokenOut Address of output token
    /// @param _idOut ERC1155 output token id
    /// @param _to Swap output recipient
    /// @param _deadline Timestamp after which swap is invalid
    function swapERC1155forExactERC1155(
        uint256 _amountOut,
        uint256 _amountInMax,
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        address _to,
        uint256 _deadline
    ) external override returns (uint256 amountIn) {
        if (block.timestamp > _deadline) {
            revert DeadlineCrossed();
        }

        IBook book = IBook(IPrinter(printer).bookForERC1155(_tokenIn, _idIn, _tokenOut, _idOut));
        bool tokenOutIsToken0 = _tokenOut == _tokenIn ? _idOut < _idIn : _tokenOut < _tokenIn;
        amountIn = _getMinAmountIn(book, _amountOut, tokenOutIsToken0 ? 0 : 1);

        if (amountIn > _amountInMax) {
            revert AmountInTooHigh(amountIn);
        }

        IERC1155(_tokenIn).safeTransferFrom(msg.sender, address(book), _idIn, amountIn, '');
        book.swap(tokenOutIsToken0 ? _amountOut : 0, tokenOutIsToken0 ? 0 : _amountOut, _to, '');
    }

    //
    // ███╗   ███╗██╗   ██╗██╗  ████████╗██╗    ███████╗████████╗███████╗██████╗ ███████╗
    // ████╗ ████║██║   ██║██║  ╚══██╔══╝██║    ██╔════╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝
    // ██╔████╔██║██║   ██║██║     ██║   ██║    ███████╗   ██║   █████╗  ██████╔╝███████╗
    // ██║╚██╔╝██║██║   ██║██║     ██║   ██║    ╚════██║   ██║   ██╔══╝  ██╔═══╝ ╚════██║
    // ██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║    ███████║   ██║   ███████╗██║     ███████║
    // ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝    ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚══════╝
    //

    /// @notice Get array of amounts for swap path for an exact input amount
    /// @dev amounts[0] is the input amount
    /// @dev amounts[amounts.length - 1] is the final output amount of the trade
    /// @dev _path is an encoded path argument that can contain both ERC20 and ERC1155 tokens
    /// @dev An ERC20 encoded element consists of [0, uint256(tokenAddress)]
    /// @dev An ERC1155 encoded element consists of [1, uint256(tokenAddress), uint256(tokenId)]
    /// @dev The amounts length is equal to the number of elements in the path, not the raw number of values in the path
    /// @param _path Encoded swap path argument
    /// @param _amountIn Exact amount in provided to swap path
    function getAmountsOut(uint256[] calldata _path, uint256 _amountIn)
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
    /// @param _path Encoded swap path argument
    /// @param _amountOut Exact amount out expected from swap path
    function getAmountsIn(uint256[] calldata _path, uint256 _amountOut)
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
    function swapExactInPath(
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
    function swapExactOutPath(
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

    //
    //  ██████╗ ██████╗ ███╗   ███╗███╗   ███╗ ██████╗ ███╗   ██╗
    // ██╔════╝██╔═══██╗████╗ ████║████╗ ████║██╔═══██╗████╗  ██║
    // ██║     ██║   ██║██╔████╔██║██╔████╔██║██║   ██║██╔██╗ ██║
    // ██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██║   ██║██║╚██╗██║
    // ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║╚██████╔╝██║ ╚████║
    //  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝
    //

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
        uint8 _decimalSum
    ) internal pure returns (uint256) {
        return ((_amountOut * (10**_decimalSum)) / _price);
    }

    function _getAmountOut(
        uint256 _amountIn,
        uint256 _price,
        uint8 _decimalSum
    ) internal pure returns (uint256) {
        return (_amountIn * _price) / 10**_decimalSum;
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
        uint8 decimalSum = _book.decimals0() + _book.decimals1();
        while (_amountIn > 0) {
            uint256 minAmountIn = _getAmountIn(order.remainingLiquidity + order.nextLiquidity, order.price, decimalSum);
            if (minAmountIn >= _amountIn) {
                amountOut += _getAmountOut(_amountIn, order.price, decimalSum);
                _amountIn = 0;
            } else {
                amountOut += _getAmountOut(minAmountIn, order.price, decimalSum);
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
        uint8 decimalSum = _book.decimals0() + _book.decimals1();
        while (_amountOut > 0) {
            uint256 maxAmountOut = order.remainingLiquidity + order.nextLiquidity;
            if (maxAmountOut >= _amountOut) {
                amountIn += _getAmountIn(_amountOut, order.price, decimalSum);
                _amountOut = 0;
            } else {
                amountIn += _getAmountIn(order.remainingLiquidity + order.nextLiquidity, order.price, decimalSum);
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
