// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

interface IPublicLibrary {
    error InsufficientLiquidity(address book, uint8 token, uint256 missingAmount);
    error DeadlineCrossed();
    error InvalidArrayLength();
    error AmountInTooHigh(uint256 amountIn);
    error AmountOutTooLow(uint256 amountOut);
    error InvalidPathArgument();
    error NullOutput();

    function printer() external view returns (address);

    function getAmountOut(
        uint256 _amountIn,
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut
    ) external view returns (uint256 amountOut);

    function getAmountIn(
        uint256 _amountOut,
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut
    ) external view returns (uint256 amountIn);

    function swapExactTokenForToken(
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountOut);

    function swapTokenForExactToken(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountOut);

    function swapMaxAbovePrice(
        uint256 _amountInMax,
        uint256 _price,
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountIn, uint256 amountOut);

    function getAmountsOut(uint256 _amountIn, uint256[] calldata _path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 _amountIn, uint256[] calldata _path) external view returns (uint256[] memory amounts);

    function swapExactIn(
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256[] calldata _path,
        address _to,
        uint256 _deadline
    ) external returns (uint256[] memory amounts);

    function swapExactOut(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[] calldata _path,
        address _to,
        uint256 _deadline
    ) external returns (uint256[] memory amounts);

    function open(
        uint256[3] calldata _tokenIn,
        uint256[3] calldata _tokenOut,
        uint256 _price,
        uint256 _amount,
        uint64 _nextOrderIndex
    ) external returns (address book, uint256 orderId);

    function closeOrder(
        address _book,
        uint256 _id,
        uint256 _amount
    ) external;

    function settle(
        address[] calldata _books,
        uint256[] calldata _orderCounts,
        uint256[] calldata _orderIds,
        address _owner
    ) external;
}
