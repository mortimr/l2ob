// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

interface IPublicLibrary {
    error InsufficientLiquidity(address book, uint8 token, uint256 maxAvailableOut);
    error DeadlineCrossed();
    error InvalidArrayLength();
    error AmountInTooHigh(uint256 amountIn);
    error AmountOutTooLow(uint256 amountOut);
    error InvalidPathArgument();

    function printer() external view returns (address);

    function getERC20ToERC20AmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut
    ) external view returns (uint256 amountIn);

    function getERC20ToERC20AmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256 amountOut);

    function openERC20ToERC20Order(
        address _tokenIn,
        address _tokenOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external returns (address book, uint256 orderId);

    function swapExactERC20forERC20(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _tokenIn,
        address _tokenOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountOut);

    function swapERC20forExactERC20(
        uint256 _amountOut,
        uint256 _amountInMax,
        address _tokenIn,
        address _tokenOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountIn);

    function getERC20ToERC1155AmountIn(
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _amountOut
    ) external view returns (uint256 amountIn);

    function getERC20ToERC1155AmountOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _amountIn
    ) external view returns (uint256 amountOut);

    function openERC20ToERC1155Order(
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external returns (address book, uint256 orderId);

    function swapExactERC20forERC1155(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountOut);

    function swapERC20forExactERC1155(
        uint256 _amountOut,
        uint256 _amountInMax,
        address _tokenIn,
        address _tokenOut,
        uint256 _idOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountIn);

    function getERC155ToERC20AmountIn(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _amountOut
    ) external view returns (uint256 amountIn);

    function getERC155ToERC20AmountOut(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256 amountOut);

    function openERC1155ToERC20Order(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external returns (address book, uint256 orderId);

    function swapExactERC1155forERC20(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountOut);

    function swapERC1155forExactERC20(
        uint256 _amountOut,
        uint256 _amountInMax,
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountIn);

    //
    // ███████╗██████╗  ██████╗ ██╗ ██╗███████╗███████╗    ████████╗ ██████╗     ███████╗██████╗  ██████╗ ██╗ ██╗███████╗███████╗
    // ██╔════╝██╔══██╗██╔════╝███║███║██╔════╝██╔════╝    ╚══██╔══╝██╔═══██╗    ██╔════╝██╔══██╗██╔════╝███║███║██╔════╝██╔════╝
    // █████╗  ██████╔╝██║     ╚██║╚██║███████╗███████╗       ██║   ██║   ██║    █████╗  ██████╔╝██║     ╚██║╚██║███████╗███████╗
    // ██╔══╝  ██╔══██╗██║      ██║ ██║╚════██║╚════██║       ██║   ██║   ██║    ██╔══╝  ██╔══██╗██║      ██║ ██║╚════██║╚════██║
    // ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║       ██║   ╚██████╔╝    ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║
    // ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝       ╚═╝    ╚═════╝     ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝
    //

    function getERC155ToERC1155AmountIn(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _amountOut
    ) external view returns (uint256 amountIn);

    function getERC155ToERC1155AmountOut(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _amountIn
    ) external view returns (uint256 amountOut);

    function openERC1155ToERC1155Order(
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external returns (address book, uint256 orderId);

    function swapExactERC1155forERC1155(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountOut);

    function swapERC1155forExactERC1155(
        uint256 _amountOut,
        uint256 _amountInMax,
        address _tokenIn,
        uint256 _idIn,
        address _tokenOut,
        uint256 _idOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountIn);

    function getAmountsOut(uint256[] calldata _path, uint256 _amountIn)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256[] calldata _path, uint256 _amountOut)
        external
        view
        returns (uint256[] memory amounts);

    function swapExactInPath(
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256[] calldata _path,
        address _to,
        uint256 _deadline
    ) external returns (uint256[] memory amounts);

    function swapExactOutPath(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[] calldata _path,
        address _to,
        uint256 _deadline
    ) external returns (uint256[] memory amounts);

    function closeOrder(
        address _book,
        uint256 _id,
        uint256 _amount
    ) external;

    function settle(
        address[] calldata _books,
        uint256[][] calldata _orderIds,
        address _owner
    ) external;
}
