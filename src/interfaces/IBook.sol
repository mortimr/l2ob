// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

interface IBook {
    error Locked();
    error Forbidden();
    error InvalidAmount();
    error ReserveTooLow();
    error InvalidBalances();
    error InvalidPriceDelta();
    error InvalidPriceOrdering();
    error MultiTokenOrderCreation();
    error NextOrderIndexOutOfBounds();
    error DecimalCountTooLow(address token);

    event Sync(uint112 reserve0, uint112 reserve1);
    event OrderChanged(uint256 indexed orderId, uint256 liquidity, uint256 remainingLiquidity, uint256 nextLiquidity);

    struct Order {
        uint64 prev;
        uint64 next;
        uint256 price;
        uint8 token;
        uint256 liquidity;
        uint256 remainingLiquidity;
        uint256 nextLiquidity;
    }

    function open(
        uint256 _price,
        uint64 _nextOrderIndex,
        address _to
    ) external;

    function close(uint256 _orderId, address _to) external;

    function settle(address _who, uint256[] calldata _orderIds) external;

    function swap(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to,
        bytes memory _data
    ) external;

    function printer() external view returns (address);

    function id0() external view returns (uint256);

    function id1() external view returns (uint256);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function head0() external view returns (Order memory);

    function head1() external view returns (Order memory);

    function erc1155_0() external view returns (bool);

    function erc1155_1() external view returns (bool);

    function decimals0() external view returns (uint8);

    function decimals1() external view returns (uint8);

    function reserve0() external view returns (uint112);

    function reserve1() external view returns (uint112);

    function orders(uint64 _index) external view returns (Order memory);

    function keyOrderIndexes(uint256 _index) external view returns (uint64);

    function totalSupply(uint256 _id) external view returns (uint256);

    function orderIndexes(uint256 _orderId) external view returns (uint64);

    function orderRounds(uint256 _orderId) external view returns (uint64);

    function rounds(address _owner, uint256 _orderId) external view returns (uint64);
}
