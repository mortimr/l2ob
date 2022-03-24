// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import './ERC1155.sol';
import './interfaces/IPairBookCaller.sol';
import './interfaces/IERC1155.sol';
import './interfaces/IERC20.sol';

//                ,   ,
//     ,   ,     /////|
//    /////|    ///// |
//   ///// |   /////  |
//  |~~~|  |  |~~~|   |
//  |===|  |  |===|   |
//  |erc|  |  |erc|   |
//  | 2 |  |  | 1 |   |
//  | 0 | /   | 1 |  /
//  |===|/    | 5 | /
//  '---'     | 5 |/
//            '---'
//
contract Book is ERC1155 {
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

    uint256 private unlocked = 2;

    address public printer;

    address public token0;
    address public token1;
    uint256 public id0;
    uint256 public id1;
    bool public erc1155_0;
    bool public erc1155_1;
    uint8 public decimals0;
    uint8 public decimals1;
    uint112 public reserve0;
    uint112 public reserve1;

    Order[] public orders;
    uint64[4] public keyOrderIndexes;

    mapping(uint256 => uint256) public totalSupply;
    mapping(uint256 => uint64) public orderIndexes;
    mapping(uint256 => uint64) public orderRounds;
    mapping(address => mapping(uint256 => uint64)) public rounds;

    uint256 internal constant BASE = 100000;
    uint256 internal constant MIN_PRICE_DELTA = 300;
    uint8 internal constant HEAD0 = 0;
    uint8 internal constant TAIL0 = 1;
    uint8 internal constant HEAD1 = 2;
    uint8 internal constant TAIL1 = 3;

    constructor() {
        printer = msg.sender;
    }

    function initialize(
        address _token0,
        uint256 _id0,
        bool _erc1155_0,
        address _token1,
        uint256 _id1,
        bool _erc1155_1
    ) external {
        if (msg.sender != printer) {
            revert Forbidden();
        }

        token0 = _token0;
        if (_erc1155_0) {
            erc1155_0 = true;
            id0 = _id0;
        } else {
            decimals0 = IERC20(token0).decimals();
        }

        token1 = _token1;
        if (_erc1155_1) {
            erc1155_1 = true;
            id1 = _id1;
        } else {
            decimals1 = IERC20(token1).decimals();
        }

        orders.push(
            Order({prev: 0, next: 0, liquidity: 0, nextLiquidity: 0, remainingLiquidity: 0, price: 0, token: 0})
        );

        keyOrderIndexes[0] = 0;
        keyOrderIndexes[1] = 0;
        keyOrderIndexes[2] = 0;
        keyOrderIndexes[3] = 0;
    }

    modifier lock() {
        if (unlocked == 1) {
            revert Locked();
        }
        unlocked = 1;
        _;
        unlocked = 2;
    }

    function head0() external view returns (Order memory) {
        return orders[keyOrderIndexes[0]];
    }

    function head1() external view returns (Order memory) {
        return orders[keyOrderIndexes[2]];
    }

    function balanceOf(address _owner, uint256 _id) external view override returns (uint256) {
        return _balanceOfComputed(_owner, _id);
    }

    function balanceOfBatch(address[] memory _owners, uint256[] memory _ids)
        external
        view
        override
        returns (uint256[] memory _balances)
    {
        uint256 ownersLength = _owners.length; // Saves MLOADs.

        require(ownersLength == _ids.length, 'LENGTH_MISMATCH');

        _balances = new uint256[](ownersLength);

        // Unchecked because the only math done is incrementing
        // the array index counter which cannot possibly overflow.
        unchecked {
            for (uint256 i = 0; i < ownersLength; ++i) {
                _balances[i] = _balanceOfComputed(_owners[i], _ids[i]);
            }
        }
    }

    function uri(uint256) public pure override returns (string memory) {
        return '';
    }

    function open(
        uint256 _price,
        uint64 _nextOrderIndex,
        address _to
    ) external lock {
        if (_nextOrderIndex >= orders.length) {
            revert NextOrderIndexOutOfBounds();
        }
        _openOrder(_price, _nextOrderIndex, _to);
    }

    function close(uint256 _orderId, address _to) external lock {
        _closeOrder(_orderId, _to);
    }

    function settle(address _who, uint256[] calldata _orderIds) external lock {
        for (uint256 i; i < _orderIds.length; ) {
            _clean(_orderIds[i], _who, _who, 0);
            unchecked {
                ++i;
            }
        }
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes memory data
    ) external lock {
        uint256 debt0;
        uint256 debt1;

        if (amount0Out > reserve0 || amount1Out > reserve1) {
            revert ReserveTooLow();
        }

        (uint256 _amount0Out, uint256 _amount1Out) = (amount0Out, amount1Out);

        if (amount0Out > 0) {
            IERC20(token0).transfer(to, amount0Out);
        }
        if (amount1Out > 0) {
            IERC20(token1).transfer(to, amount1Out);
        }

        while (_amount0Out > 0 || _amount1Out > 0) {
            if (_amount0Out > 0) {
                uint64 headIndex = _getHeadIndex(0);
                if (headIndex > 0) {
                    uint256 debt;
                    (_amount0Out, debt) = _swapFromOrder(headIndex, _amount0Out);
                    debt1 += debt;
                } else {
                    revert ReserveTooLow();
                }
            }
            if (_amount1Out > 0) {
                uint64 headIndex = _getHeadIndex(1);
                if (headIndex > 0) {
                    uint256 debt;
                    (_amount1Out, debt) = _swapFromOrder(headIndex, _amount1Out);
                    debt0 += debt;
                } else {
                    revert ReserveTooLow();
                }
            }
        }

        if (data.length > 0) {
            IPairBookCaller(to).pairBookCallback(amount0Out, amount1Out, debt0, debt1, msg.sender, data);
        }

        uint256 balance0 = _balance(0, address(this));
        uint256 balance1 = _balance(1, address(this));

        if (
            (reserve0 + debt0 < amount0Out || balance0 < reserve0 + debt0 - amount0Out) ||
            (reserve1 + debt1 < amount1Out || balance1 < reserve1 + debt1 - amount1Out)
        ) {
            revert InvalidBalances();
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        emit Sync(reserve0, reserve1);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        require(msg.sender == from || isApprovedForAll[from][msg.sender], 'NOT_AUTHORIZED');

        if (id & 1 == 1) {
            // transferring rewards
            _clean(id - 1, from, to, amount); // clean balance, and send filled tokens relative to amount sent to recipient
            _clean(id - 1, to, to, 0); // clean recipient balance
        } else {
            _clean(id, from, to, amount); // clean balance, and send filled tokens relative to amount sent to recipient
            _clean(id, to, to, 0); // clean recipient balance

            _balanceOf[from][id] -= amount;
            _balanceOf[to][id] += amount;

            emit TransferSingle(msg.sender, from, to, id, amount);

            require(
                to.code.length == 0
                    ? to != address(0)
                    : to == address(this) ||
                        ERC1155TokenReceiver(to).onERC1155Received(msg.sender, from, id, amount, data) ==
                        ERC1155TokenReceiver.onERC1155Received.selector,
                'UNSAFE_RECIPIENT'
            );
        }
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        uint256 idsLength = ids.length; // Saves MLOADs.

        require(idsLength == amounts.length, 'LENGTH_MISMATCH');

        require(msg.sender == from || isApprovedForAll[from][msg.sender], 'NOT_AUTHORIZED');

        // Storing these outside the loop saves ~15 gas per iteration.
        uint256 id;
        uint256 amount;

        for (uint256 i = 0; i < idsLength; ) {
            id = ids[i];
            amount = amounts[i];
            if (id & 1 == 1) {
                _clean(id - 1, from, to, amount);
                _clean(id - 1, to, to, 0);
                amounts[i] = 0;
            } else {
                _clean(id, from, to, amount);
                _clean(id, to, to, 0);

                _balanceOf[from][id] -= amount;
                _balanceOf[to][id] += amount;
            }

            // An array can't have a total length
            // larger than the max uint256 value.
            unchecked {
                ++i;
            }
        }

        emit TransferBatch(msg.sender, from, to, ids, amounts);

        require(
            to.code.length == 0
                ? to != address(0)
                : to == address(this) ||
                    ERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, data) ==
                    ERC1155TokenReceiver.onERC1155BatchReceived.selector,
            'UNSAFE_RECIPIENT'
        );
    }

    function _getOrderId(uint8 _token, uint256 _price) internal pure returns (uint256 id) {
        id = _price;
        id = id << 1;
        id += _token;
        id = id << 1;
    }

    function _checkDelta(uint256 _basePrice, uint256 _newPrice) internal pure returns (bool) {
        if (_basePrice > _newPrice) {
            return (_basePrice - _newPrice) > (_basePrice * MIN_PRICE_DELTA) / BASE;
        } else {
            return (_newPrice - _basePrice) > (_basePrice * MIN_PRICE_DELTA) / BASE;
        }
    }

    function _checkAfterOrder(Order memory _order, uint256 _price) internal pure {
        if (_price >= _order.price) {
            revert InvalidPriceOrdering();
        }
        if (!_checkDelta(_order.price, _price)) {
            revert InvalidPriceDelta();
        }
    }

    function _checkBeforeOrder(Order memory _order, uint256 _price) internal pure {
        if (_price <= _order.price) {
            revert InvalidPriceOrdering();
        }
        if (!_checkDelta(_order.price, _price)) {
            revert InvalidPriceDelta();
        }
    }

    function _balanceOfComputed(address _owner, uint256 _id) internal view returns (uint256) {
        if (_id & 1 == 1) {
            // reward token
            uint256 realId = _id - 1;
            uint256 balance = _balanceOf[_owner][realId];

            if (balance == 0) {
                return 0;
            }

            uint256 orderIndex = orderIndexes[realId];

            if (orderIndex > 0) {
                Order memory order = orders[orderIndex];
                if (rounds[_owner][realId] > orderRounds[realId]) {
                    // 0% filled
                    return 0;
                } else if (rounds[_owner][realId] == orderRounds[realId]) {
                    // partial fill
                    balance = (balance * (order.liquidity - order.remainingLiquidity)) / order.liquidity;
                }
            }

            uint256 price = _id >> 2;

            return (balance * price) / (10**(decimals0 + decimals1));
        } else {
            // order token
            uint256 balance = _balanceOf[_owner][_id];

            if (balance == 0) {
                return 0;
            }

            uint256 orderIndex = orderIndexes[_id];

            if (orderIndex == 0) {
                // 100% filled
                return 0;
            }

            if (rounds[_owner][_id] > orderRounds[_id]) {
                // 0% filled
                return balance;
            } else if (rounds[_owner][_id] == orderRounds[_id]) {
                // partial fill
                Order memory order = orders[orderIndex];
                return (balance * order.remainingLiquidity) / order.liquidity;
            } else {
                // 100% filled
                return 0;
            }
        }
    }

    function _balance(uint8 _asset, address _owner) internal view returns (uint256) {
        if (_asset == 0) {
            if (erc1155_0) {
                return IERC1155(token0).balanceOf(_owner, id0);
            } else {
                return IERC20(token0).balanceOf(_owner);
            }
        } else {
            if (erc1155_1) {
                return IERC1155(token1).balanceOf(_owner, id1);
            } else {
                return IERC20(token1).balanceOf(_owner);
            }
        }
    }

    function _getHeadIndex(uint8 token) internal view returns (uint64) {
        if (token == 0) {
            return keyOrderIndexes[HEAD0];
        } else {
            return keyOrderIndexes[HEAD1];
        }
    }

    function _getTailIndex(uint8 token) internal view returns (uint64) {
        if (token == 0) {
            return keyOrderIndexes[TAIL0];
        } else {
            return keyOrderIndexes[TAIL1];
        }
    }

    function _getAmountIn(uint256 amountOut, uint256 price) internal view returns (uint256) {
        return ((amountOut * price) / (10**(decimals0 + decimals1)));
    }

    function _getAmountOut(uint256 amountIn, uint256 price) internal view returns (uint256) {
        return (amountIn * price) / 10**(decimals0 + decimals1);
    }

    function _transferOut(
        uint8 _asset,
        address _recipient,
        uint256 _amount
    ) internal {
        if (_asset == 0) {
            if (erc1155_0) {
                IERC1155(token0).safeTransferFrom(address(this), _recipient, id0, _amount, '');
            } else {
                IERC20(token0).transfer(_recipient, _amount);
            }
        } else {
            if (erc1155_1) {
                IERC1155(token1).safeTransferFrom(address(this), _recipient, id1, _amount, '');
            } else {
                IERC20(token1).transfer(_recipient, _amount);
            }
        }
    }

    function _setHeadIndex(uint8 token, uint64 idx) internal {
        if (token == 0) {
            keyOrderIndexes[HEAD0] = idx;
        } else {
            keyOrderIndexes[HEAD1] = idx;
        }
    }

    function _setTailIndex(uint8 token, uint64 idx) internal {
        if (token == 0) {
            keyOrderIndexes[TAIL0] = idx;
        } else {
            keyOrderIndexes[TAIL1] = idx;
        }
    }

    function _insertOrder(
        uint8 _token,
        uint256 _price,
        uint64 _nextOrderIndex
    ) internal returns (uint256, uint256) {
        uint256 orderId = _getOrderId(_token, _price);
        uint64 headIndex = _getHeadIndex(_token);
        uint64 tailIndex = _getTailIndex(_token);
        if (headIndex == 0) {
            orders.push(
                Order({
                    prev: 0,
                    next: 0,
                    liquidity: 0,
                    remainingLiquidity: 0,
                    nextLiquidity: 0,
                    price: _price,
                    token: _token
                })
            );
            uint64 newOrderIndex = uint64(orders.length) - 1;
            orderIndexes[orderId] = newOrderIndex;
            _setHeadIndex(_token, newOrderIndex);
            _setTailIndex(_token, newOrderIndex);

            return (orderId, newOrderIndex);
        } else if (_nextOrderIndex == 0) {
            Order memory tailOrder = orders[tailIndex];
            _checkAfterOrder(tailOrder, _price);
            orders.push(
                Order({
                    prev: tailIndex,
                    next: 0,
                    liquidity: 0,
                    remainingLiquidity: 0,
                    nextLiquidity: 0,
                    price: _price,
                    token: _token
                })
            );
            uint64 newOrderIndex = uint64(orders.length) - 1;
            orderIndexes[orderId] = newOrderIndex;
            orders[tailIndex].next = newOrderIndex;
            _setTailIndex(_token, newOrderIndex);
            return (orderId, newOrderIndex);
        } else {
            Order memory nextOrder = orders[_nextOrderIndex];
            if (nextOrder.price == _price) {
                return (orderId, _nextOrderIndex);
            } else if (nextOrder.prev == 0) {
                _checkBeforeOrder(nextOrder, _price);
                orders.push(
                    Order({
                        prev: 0,
                        next: _nextOrderIndex,
                        liquidity: 0,
                        remainingLiquidity: 0,
                        nextLiquidity: 0,
                        price: _price,
                        token: _token
                    })
                );
                uint64 newOrderIndex = uint64(orders.length) - 1;
                orderIndexes[orderId] = newOrderIndex;
                orders[_nextOrderIndex].prev = newOrderIndex;
                _setHeadIndex(_token, newOrderIndex);
                return (orderId, newOrderIndex);
            } else {
                Order memory prevOrder = orders[nextOrder.prev];
                _checkBeforeOrder(nextOrder, _price);
                _checkAfterOrder(prevOrder, _price);
                orders.push(
                    Order({
                        prev: nextOrder.prev,
                        next: _nextOrderIndex,
                        liquidity: 0,
                        remainingLiquidity: 0,
                        nextLiquidity: 0,
                        price: _price,
                        token: _token
                    })
                );
                uint64 newOrderIndex = uint64(orders.length) - 1;
                orderIndexes[orderId] = newOrderIndex;
                orders[nextOrder.prev].next = newOrderIndex;
                orders[_nextOrderIndex].prev = newOrderIndex;

                return (orderId, newOrderIndex);
            }
        }
    }

    function _mintOrdersToken(
        uint256 _orderId,
        uint256 _orderIndex,
        uint256 _amount,
        address _to
    ) internal {
        _mintTokens(_to, _orderId, _amount);
        if (orders[_orderIndex].remainingLiquidity == orders[_orderIndex].liquidity) {
            orders[_orderIndex].liquidity += _amount;
            orders[_orderIndex].remainingLiquidity += _amount;
        } else {
            orders[_orderIndex].nextLiquidity += _amount;
        }

        emit OrderChanged(
            _orderId,
            orders[_orderIndex].liquidity,
            orders[_orderIndex].remainingLiquidity,
            orders[_orderIndex].nextLiquidity
        );
    }

    function _increaseOrderReserves(uint112 _amount0In, uint112 _amount1In) internal {
        if (_amount0In > 0) {
            reserve0 += _amount0In;
        }
        if (_amount1In > 0) {
            reserve1 += _amount1In;
        }
        emit Sync(reserve0, reserve1);
    }

    function _decreaseOrderReserves(uint112 _amount0Out, uint112 _amount1Out) internal {
        if (_amount0Out > 0) {
            reserve0 -= _amount0Out;
        }
        if (_amount1Out > 0) {
            reserve1 -= _amount1Out;
        }
        emit Sync(reserve0, reserve1);
    }

    function _openOrder(
        uint256 _price,
        uint64 _nextOrderIndex,
        address _to
    ) internal {
        uint256 amount0In = _balance(0, address(this)) - reserve0;
        uint256 amount1In = _balance(1, address(this)) - reserve1;

        if (!(amount0In * amount1In == 0 && (amount0In > 0 || amount1In > 0))) {
            revert MultiTokenOrderCreation();
        }

        uint8 token = amount0In > amount1In ? 0 : 1;
        uint256 amountIn = amount0In > amount1In ? amount0In : amount1In;
        (uint256 orderId, uint256 orderIndex) = _insertOrder(token, _price, _nextOrderIndex);
        _mintOrdersToken(orderId, orderIndex, amountIn, _to);
        Order memory order = orders[orderIndex];

        if (order.liquidity != order.remainingLiquidity) {
            rounds[_to][orderId] = orderRounds[orderId] + 1;
        } else {
            rounds[_to][orderId] = orderRounds[orderId];
        }

        _increaseOrderReserves(uint112(amount0In), uint112(amount1In));
    }

    function _clean(
        uint256 _orderId,
        address _owner,
        address _to,
        uint256 _amount
    ) internal {
        uint64 index = orderIndexes[_orderId];
        Order memory order = orders[index];
        _bringToUntouchedRound(_orderId, index, order, _owner, _to, _amount);
    }

    function _bringToUntouchedRound(
        uint256 _orderId,
        uint64 _orderIndex,
        Order memory _order,
        address _owner,
        address _to,
        uint256 _amount
    ) internal {
        if (_orderIndex == 0) {
            uint256 balance = _balanceOf[_owner][_orderId];
            if (_amount > balance) {
                revert InvalidAmount();
            }
            if (balance == 0) {
                return;
            }
            uint256 price = _orderId >> 2;
            uint8 orderOutputToken = (uint8((_orderId >> 1) & 1)) ^ 1;
            uint256 orderAmountOut;
            if (_amount == 0 || _amount == balance) {
                orderAmountOut = _getAmountOut(balance, price);
                _transferOut(orderOutputToken, _to, orderAmountOut);
            } else {
                uint256 orderToAmountOut = _getAmountOut(_amount, price);
                _transferOut(orderOutputToken, _to, orderToAmountOut);
                uint256 orderOwnerAmountOut = _getAmountOut(balance - _amount, price);
                _transferOut(orderOutputToken, _to, orderOwnerAmountOut);
                orderAmountOut = orderToAmountOut + orderOwnerAmountOut;
            }
            _decreaseOrderReserves(
                uint112(orderOutputToken == 0 ? orderAmountOut : 0),
                uint112(orderOutputToken == 1 ? orderAmountOut : 0)
            );
            _burnTokens(_owner, _orderId, balance);
            if (rounds[_owner][_orderId] > 0) {
                rounds[_owner][_orderId] = 0;
            }
            // check if user have balance, derive price + token from id
        } else {
            uint64 untouchedRound = orderRounds[_orderId];
            if (_order.liquidity != _order.remainingLiquidity) {
                untouchedRound += 1;
            }
            uint64 ownerRound = rounds[_owner][_orderId];

            if (ownerRound >= untouchedRound) {
                return;
            }

            uint256 rawBalance = _balanceOf[_owner][_orderId];
            uint256 balance = rawBalance;

            if (ownerRound == orderRounds[_orderId]) {
                // not 100% filled
                balance = (balance * (_order.liquidity - _order.remainingLiquidity)) / _order.liquidity;
            }

            if (balance == 0) {
                return;
            }

            uint256 orderAmountOut = _getAmountOut(balance, _order.price);
            if (_amount == 0 || _amount == balance) {
                orderAmountOut = _getAmountOut(balance, _order.price);
                _transferOut(_order.token ^ 1, _to, orderAmountOut);
            } else {
                uint256 orderToAmountOut = _getAmountOut(_amount, _order.price);
                _transferOut(_order.token ^ 1, _to, orderToAmountOut);
                uint256 orderOwnerAmountOut = _getAmountOut(balance - _amount, _order.price);
                _transferOut(_order.token ^ 1, _to, orderOwnerAmountOut);
                orderAmountOut = orderToAmountOut + orderOwnerAmountOut;
            }
            _decreaseOrderReserves(
                uint112(_order.token == 1 ? orderAmountOut : 0),
                uint112(_order.token == 0 ? orderAmountOut : 0)
            );
            _burnTokens(_owner, _orderId, balance);

            if (totalSupply[_orderId] == 0) {
                _removeOrder(_orderId, _orderIndex);
            } else {
                if (rawBalance > balance) {
                    // partial fill

                    rounds[_owner][_orderId] = untouchedRound; // user is brought to untouchedRound

                    if (orders[_orderIndex].liquidity == rawBalance) {
                        // if all liquidity is moving to untouched, bring order to next round
                        uint256 newLiq = rawBalance - balance + orders[_orderIndex].nextLiquidity;
                        orders[_orderIndex].liquidity = newLiq;
                        orders[_orderIndex].remainingLiquidity = newLiq;
                        orders[_orderIndex].nextLiquidity = 0;
                        orderRounds[_orderId] += 1;
                    } else {
                        // otherwise, compute unfilled amount and add it to nextLiquidity
                        orders[_orderIndex].nextLiquidity += rawBalance - balance;
                        orders[_orderIndex].liquidity -= rawBalance;
                        orders[_orderIndex].remainingLiquidity -= rawBalance - balance;
                    }
                } else {
                    // total fill
                    // total fill can only happen in round id < current round id, meaning it has no impact in current liquidity
                    rounds[_owner][_orderId] = 0;
                }
            }
        }
    }

    function _mintTokens(
        address _to,
        uint256 _id,
        uint256 _amount
    ) internal {
        ERC1155._mint(_to, _id, _amount, '');
        totalSupply[_id] += _amount;
    }

    function _burnTokens(
        address _from,
        uint256 _id,
        uint256 _amount
    ) internal {
        ERC1155._burn(_from, _id, _amount);
        totalSupply[_id] -= _amount;
    }

    function _removeOrder(uint256 _orderId, uint64 _orderIndex) internal {
        Order memory order = orders[_orderIndex];

        if (order.next != 0) {
            orders[order.next].prev = order.prev;
        } else {
            _setTailIndex(order.token, order.prev);
        }
        if (order.prev != 0) {
            orders[order.prev].next = order.next;
        } else {
            _setHeadIndex(order.token, order.next);
        }

        if (_orderIndex != orders.length - 1) {
            Order memory lastOrder = orders[orders.length - 1];

            if (lastOrder.next != 0) {
                orders[lastOrder.next].prev = _orderIndex;
            } else {
                _setTailIndex(lastOrder.token, _orderIndex);
            }
            if (lastOrder.prev != 0) {
                orders[lastOrder.prev].next = _orderIndex;
            } else {
                _setHeadIndex(lastOrder.token, _orderIndex);
            }
            uint256 lastOrderId = _getOrderId(lastOrder.token, lastOrder.price);
            orderIndexes[lastOrderId] = _orderIndex;
            orders[_orderIndex] = lastOrder;
            orderIndexes[_orderId] = 0;
            orders.pop();
        } else {
            orderIndexes[_orderId] = 0;
            orders.pop();
        }

        emit OrderChanged(_orderId, 0, 0, 0);
    }

    function _closeOrder(uint256 _orderId, address _to) internal {
        uint64 orderIndex = orderIndexes[_orderId];
        Order memory order = orders[orderIndex];
        _bringToUntouchedRound(_orderId, orderIndex, order, address(this), _to, 0);
        uint256 orderAmountIn = _balanceOf[address(this)][_orderId];
        if (orderAmountIn == 0) {
            return;
        }
        _transferOut(order.token, _to, orderAmountIn);
        _burnTokens(address(this), _orderId, orderAmountIn);
        _decreaseOrderReserves(
            uint112(order.token == 0 ? orderAmountIn : 0),
            uint112(order.token == 1 ? orderAmountIn : 0)
        );
        if (totalSupply[_orderId] == 0) {
            _removeOrder(_orderId, orderIndex);
        }
    }

    function _consumeFromOrderPartialLiq(
        Order memory order,
        uint64 orderIndex,
        uint256 amountOut
    ) internal returns (uint256 amountOutLeft, uint256 debt) {
        uint256 orderId = _getOrderId(order.token, order.price);
        orders[orderIndex].remainingLiquidity -= amountOut;

        amountOutLeft = 0;
        debt = _getAmountIn(amountOut, order.price);

        emit OrderChanged(
            orderId,
            orders[orderIndex].liquidity,
            orders[orderIndex].remainingLiquidity,
            orders[orderIndex].nextLiquidity
        );
    }

    function _consumeFromOrderNextLiq(
        Order memory order,
        uint64 orderIndex,
        uint256 amountOut
    ) internal returns (uint256 amountOutLeft, uint256 debt) {
        uint256 orderId = _getOrderId(order.token, order.price);
        if (amountOut >= order.nextLiquidity) {
            amountOutLeft = amountOut - order.nextLiquidity;
            debt = _getAmountIn(order.nextLiquidity + orders[orderIndex].remainingLiquidity, order.price);

            _removeOrder(_getOrderId(order.token, order.price), orderIndex);
        } else {
            debt = _getAmountIn(amountOut + orders[orderIndex].remainingLiquidity, order.price);
            orders[orderIndex].remainingLiquidity = orders[orderIndex].nextLiquidity - amountOut;
            orders[orderIndex].liquidity = orders[orderIndex].nextLiquidity;
            orderRounds[orderId] += 1;
            orders[orderIndex].nextLiquidity = 0;

            amountOutLeft = 0;

            emit OrderChanged(orderId, orders[orderIndex].liquidity, orders[orderIndex].remainingLiquidity, 0);
        }
    }

    function _swapFromOrder(uint64 firstOrderIndex, uint256 amountOut)
        internal
        returns (
            uint256, /* amountOutLeft */
            uint256 /* debt */
        )
    {
        Order memory order = orders[firstOrderIndex];
        uint256 availableLiquidity = order.remainingLiquidity;
        if (amountOut >= availableLiquidity) {
            return _consumeFromOrderNextLiq(order, firstOrderIndex, amountOut - availableLiquidity);
        } else {
            return _consumeFromOrderPartialLiq(order, firstOrderIndex, amountOut);
        }
    }
}
