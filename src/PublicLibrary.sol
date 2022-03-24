// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import './interfaces/IERC1155.sol';
import './interfaces/IERC20.sol';
import './interfaces/IBook.sol';
import './interfaces/IPrinter.sol';

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
contract PublicLibrary {
    IPrinter public printer;

    constructor(address _printer) {
        printer = IPrinter(_printer);
    }

    function openERC20Order(
        address _tokenIn,
        address _tokenOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external {
        IBook book = IBook(printer.pairForERC20(_tokenIn, _tokenOut));

        if (address(book) == address(0)) {
            book = IBook(printer.createERC20Pair(_tokenIn, _tokenOut));
        }

        IERC20(_tokenIn).transferFrom(msg.sender, address(book), _amount);
        book.open(_price, _nextOrderIndex, msg.sender);
    }

    function openERC1155Order(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external {
        IBook book = IBook(printer.pairForERC1155(_tokenIn, _idIn, _tokenOut, _idOut));

        if (address(book) == address(0)) {
            book = IBook(printer.createERC1155Pair(_tokenIn, _idIn, _tokenOut, _idOut));
        }

        IERC1155(_tokenIn).safeTransferFrom(msg.sender, address(book), _idIn, _amount, '');
        book.open(_price, _nextOrderIndex, msg.sender);
    }

    function openERC1155ToERC20Order(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external {
        IBook book = IBook(printer.pairForHybrid(_tokenIn, _idIn, _tokenOut));

        if (address(book) == address(0)) {
            book = IBook(printer.createHybridPair(_tokenIn, _idIn, _tokenOut));
        }

        IERC1155(_tokenIn).safeTransferFrom(msg.sender, address(book), _idIn, _amount, '');
        book.open(_price, _nextOrderIndex, msg.sender);
    }

    function openERC20ToERC1155Order(
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external {
        IBook book = IBook(printer.pairForHybrid(_tokenOut, _idOut, _tokenIn));

        if (address(book) == address(0)) {
            book = IBook(printer.createHybridPair(_tokenOut, _idOut, _tokenIn));
        }

        IERC20(_tokenIn).transferFrom(msg.sender, address(book), _amount);
        book.open(_price, _nextOrderIndex, msg.sender);
    }

    function closeOrder(
        address _book,
        uint256 _id,
        uint256 _amount
    ) external {
        IERC1155(_book).safeTransferFrom(msg.sender, address(_book), _id, _amount, '');
        IBook(_book).close(_id, msg.sender);
    }
}
