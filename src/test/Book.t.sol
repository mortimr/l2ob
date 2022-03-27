// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import 'solmate/test/utils/DSTestPlus.sol';
import 'solmate/tokens/ERC20.sol';
import 'forge-std/Vm.sol';

import './console.sol';

import '../Book.sol';

contract ERC20Mock is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract BookTest is DSTestPlus {
    Vm public constant vm = Vm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    Book internal pb;
    ERC20Mock internal token0;
    ERC20Mock internal token1;

    address internal bob = address(1);
    address internal alice = address(2);

    function setUp() public {
        pb = new Book();
        token0 = new ERC20Mock('US Dollar', 'USDC', 6);
        token1 = new ERC20Mock('Wrapped Ether', 'WETH', 18);
        pb.initialize(address(token0), 0, false, address(token1), 0, false);
    }

    function testOpenOrderWithoutInputToken() public {
        uint256 price = 10**(18 + 6);
        vm.expectRevert(abi.encodeWithSignature('MultiTokenOrderCreation()'));
        pb.open(price, 0, bob);
    }

    function testOpenOrderT0() public {
        {
            uint256 price = 10**(18 + 6);
            uint256 orderSize = 100 ether;
            token0.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(0) == 0);
            assert(pb.keyOrderIndexes(1) == 0);
            startMeasuringGas('open T0');
            pb.open(price, 0, bob);
            stopMeasuringGas();
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
        }
        {
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
        }
    }

    function testOpenOrderT1() public {
        {
            uint256 price = 10**(18 + 6);
            uint256 orderSize = 100 ether;
            token1.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(2) == 0);
            assert(pb.keyOrderIndexes(3) == 0);
            startMeasuringGas('open T1');
            pb.open(price, 0, bob);
            stopMeasuringGas();
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
        }
        {
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
        }
    }

    function checkIndexes(
        uint64[] memory indexes,
        uint64 orderIndex,
        uint64 arrayIndex
    ) internal view {
        IBook.Order memory order = pb.orders(orderIndex);
        assert(order.prev == indexes[arrayIndex]);
        assert(order.next == indexes[arrayIndex + 1]);
    }

    function testOpenFiveAndCloseOrdersT0() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;
        for (uint256 i; i < 5; ++i) {
            token0.mint(address(pb), orderSize);
            vm.startPrank(bob);
            pb.open(price, uint64(i), bob);
            price += ((price * 300) / 100000) + 1;
            vm.stopPrank();
        }
        uint64[] memory indexes = new uint64[](10);

        indexes[0] = 2;
        // 1
        indexes[1] = 0;

        indexes[2] = 3;
        // 2
        indexes[3] = 1;

        indexes[4] = 4;
        // 3
        indexes[5] = 2;

        indexes[6] = 5;
        // 4
        indexes[7] = 3;

        indexes[8] = 0;
        // 5
        indexes[9] = 4;

        checkIndexes(indexes, 1, 0);
        checkIndexes(indexes, 2, 2);
        checkIndexes(indexes, 3, 4);
        checkIndexes(indexes, 4, 6);
        checkIndexes(indexes, 5, 8);

        price = 10**(18 + 6);
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;

        vm.startPrank(bob);
        pb.safeTransferFrom(bob, address(pb), price << 2, pb.balanceOf(bob, price << 2), '');
        vm.stopPrank();

        pb.close(price << 2, bob); // removing 3

        indexes[0] = 2;
        // 1
        indexes[1] = 0;

        indexes[2] = 4;
        // 2
        indexes[3] = 1;

        indexes[4] = 0;
        // 3 (previous 5)
        indexes[5] = 4;

        indexes[6] = 3;
        // 4
        indexes[7] = 2;

        checkIndexes(indexes, 1, 0);
        checkIndexes(indexes, 2, 2);
        checkIndexes(indexes, 3, 4);
        checkIndexes(indexes, 4, 6);

        price = 10**(18 + 6);
        price += ((price * 300) / 100000) + 1;

        vm.startPrank(bob);
        pb.safeTransferFrom(bob, address(pb), price << 2, pb.balanceOf(bob, price << 2), '');
        vm.stopPrank();

        pb.close(price << 2, bob); // removing 2

        indexes[0] = 2;
        // 1
        indexes[1] = 0;

        indexes[2] = 3;
        // 2 (previous 4)
        indexes[3] = 1;

        indexes[4] = 0;
        // 3
        indexes[5] = 2;

        checkIndexes(indexes, 1, 0);
        checkIndexes(indexes, 2, 2);
        checkIndexes(indexes, 3, 4);

        price = 10**(18 + 6);
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;

        vm.startPrank(bob);
        pb.safeTransferFrom(bob, address(pb), price << 2, pb.balanceOf(bob, price << 2), '');
        vm.stopPrank();

        pb.close(price << 2, bob); // removing 2

        indexes[0] = 2;
        // 1
        indexes[1] = 0;

        indexes[2] = 0;
        // 2 (previous 3)
        indexes[3] = 1;

        checkIndexes(indexes, 1, 0);
        checkIndexes(indexes, 2, 2);

        price = 10**(18 + 6);

        vm.startPrank(bob);
        pb.safeTransferFrom(bob, address(pb), price << 2, pb.balanceOf(bob, price << 2), '');
        vm.stopPrank();

        pb.close(price << 2, bob); // removing 1

        indexes[0] = 0;
        // 1 (previous 2)
        indexes[1] = 0;

        checkIndexes(indexes, 1, 0);

        price = 10**(18 + 6);
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;

        vm.startPrank(bob);
        pb.safeTransferFrom(bob, address(pb), price << 2, pb.balanceOf(bob, price << 2), '');
        vm.stopPrank();

        pb.close(price << 2, bob); // removing last one

        assert(pb.keyOrderIndexes(0) == 0);
        assert(pb.keyOrderIndexes(1) == 0);
    }

    function testOpenFiveAndCloseOrdersT1() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;
        for (uint256 i; i < 5; ++i) {
            token1.mint(address(pb), orderSize);
            vm.startPrank(bob);
            pb.open(price, uint64(i), bob);
            price += ((price * 300) / 100000) + 1;
            vm.stopPrank();
        }
        uint64[] memory indexes = new uint64[](10);

        indexes[0] = 2;
        // 1
        indexes[1] = 0;

        indexes[2] = 3;
        // 2
        indexes[3] = 1;

        indexes[4] = 4;
        // 3
        indexes[5] = 2;

        indexes[6] = 5;
        // 4
        indexes[7] = 3;

        indexes[8] = 0;
        // 5
        indexes[9] = 4;

        checkIndexes(indexes, 1, 0);
        checkIndexes(indexes, 2, 2);
        checkIndexes(indexes, 3, 4);
        checkIndexes(indexes, 4, 6);
        checkIndexes(indexes, 5, 8);

        price = 10**(18 + 6);
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;

        vm.startPrank(bob);
        pb.safeTransferFrom(bob, address(pb), ((price << 1) + 1) << 1, pb.balanceOf(bob, ((price << 1) + 1) << 1), '');
        vm.stopPrank();

        pb.close(((price << 1) + 1) << 1, bob); // removing 3

        indexes[0] = 2;
        // 1
        indexes[1] = 0;

        indexes[2] = 4;
        // 2
        indexes[3] = 1;

        indexes[4] = 0;
        // 3 (previous 5)
        indexes[5] = 4;

        indexes[6] = 3;
        // 4
        indexes[7] = 2;

        checkIndexes(indexes, 1, 0);
        checkIndexes(indexes, 2, 2);
        checkIndexes(indexes, 3, 4);
        checkIndexes(indexes, 4, 6);

        price = 10**(18 + 6);
        price += ((price * 300) / 100000) + 1;

        vm.startPrank(bob);
        pb.safeTransferFrom(bob, address(pb), ((price << 1) + 1) << 1, pb.balanceOf(bob, ((price << 1) + 1) << 1), '');
        vm.stopPrank();

        pb.close(((price << 1) + 1) << 1, bob); // removing 2

        indexes[0] = 2;
        // 1
        indexes[1] = 0;

        indexes[2] = 3;
        // 2 (previous 4)
        indexes[3] = 1;

        indexes[4] = 0;
        // 3
        indexes[5] = 2;

        checkIndexes(indexes, 1, 0);
        checkIndexes(indexes, 2, 2);
        checkIndexes(indexes, 3, 4);

        price = 10**(18 + 6);
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;

        vm.startPrank(bob);
        pb.safeTransferFrom(bob, address(pb), ((price << 1) + 1) << 1, pb.balanceOf(bob, ((price << 1) + 1) << 1), '');
        vm.stopPrank();

        pb.close(((price << 1) + 1) << 1, bob); // removing 2

        indexes[0] = 2;
        // 1
        indexes[1] = 0;

        indexes[2] = 0;
        // 2 (previous 3)
        indexes[3] = 1;

        checkIndexes(indexes, 1, 0);
        checkIndexes(indexes, 2, 2);

        price = 10**(18 + 6);

        vm.startPrank(bob);
        pb.safeTransferFrom(bob, address(pb), ((price << 1) + 1) << 1, pb.balanceOf(bob, ((price << 1) + 1) << 1), '');
        vm.stopPrank();

        pb.close(((price << 1) + 1) << 1, bob); // removing 1

        indexes[0] = 0;
        // 1 (previous 2)
        indexes[1] = 0;

        checkIndexes(indexes, 1, 0);

        price = 10**(18 + 6);
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;
        price += ((price * 300) / 100000) + 1;

        vm.startPrank(bob);
        pb.safeTransferFrom(bob, address(pb), ((price << 1) + 1) << 1, pb.balanceOf(bob, ((price << 1) + 1) << 1), '');
        vm.stopPrank();

        pb.close(((price << 1) + 1) << 1, bob); // removing last one

        assert(pb.keyOrderIndexes(0) == 0);
        assert(pb.keyOrderIndexes(1) == 0);
    }

    function testFillOrderT0() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;
        {
            token0.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(0) == 0);
            assert(pb.keyOrderIndexes(1) == 0);
            pb.open(price, 0, bob);
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
        }
        {
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
        }
        {
            uint256 amount1In = (orderSize * price) / (10**(18 + 6));
            token1.mint(address(pb), amount1In);
            assert(token0.balanceOf(bob) == 0);
            startMeasuringGas('swap T1T0');
            pb.swap(orderSize, 0, bob, '');
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == orderSize);
        }
        {
            uint256 expectedPayout = (orderSize * price) / (10**(18 + 6));
            assert(token1.balanceOf(bob) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = price << 2;
            startMeasuringGas('settle');
            pb.settle(bob, ids);
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == expectedPayout);
        }
    }

    function testFillOrderT1() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;
        {
            token1.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(2) == 0);
            assert(pb.keyOrderIndexes(3) == 0);
            pb.open(price, 0, bob);
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
        }
        {
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
        }
        {
            uint256 amount0In = (orderSize * price) / (10**(18 + 6));
            token0.mint(address(pb), amount0In);
            assert(token1.balanceOf(bob) == 0);
            startMeasuringGas('swap T0T1');
            pb.swap(0, orderSize, bob, '');
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == orderSize);
        }
        {
            uint256 expectedPayout = (orderSize * price) / (10**(18 + 6));
            assert(token0.balanceOf(bob) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = ((price << 1) + 1) << 1;
            startMeasuringGas('settle');
            pb.settle(bob, ids);
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == expectedPayout);
        }
    }

    function testFillTwoOrdersT1() public {
        uint256 price0 = 10**(18 + 6);
        uint256 price1 = price0 + (((price0 * 300) / 100000) + 1);
        uint256 order0 = ((price0 << 1) + 1) << 1;
        uint256 order1 = ((price1 << 1) + 1) << 1;
        uint256 orderSize = 100 ether;
        {
            token1.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(2) == 0);
            assert(pb.keyOrderIndexes(3) == 0);
            pb.open(price0, 0, bob);
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
            vm.stopPrank();
        }
        {
            token1.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
            pb.open(price1, 1, bob);
            assert(pb.keyOrderIndexes(2) == 2);
            assert(pb.keyOrderIndexes(3) == 1);
            vm.stopPrank();
        }
        {
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 2);
            assert(order.next == 0);
            assert(order.price == price0);
            assert(order.token == 1);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(order0) == 0);
            assert(pb.rounds(bob, order0) == 0);
        }
        {
            IBook.Order memory order = pb.orders(2);
            assert(order.prev == 0);
            assert(order.next == 1);
            assert(order.price == price1);
            assert(order.token == 1);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(order1) == 0);
            assert(pb.rounds(bob, order1) == 0);
        }
        {
            uint256 amount0In = ((orderSize * price0) / (10**(18 + 6))) + ((orderSize * price1) / (10**(18 + 6)));
            token0.mint(address(pb), amount0In);
            assert(token1.balanceOf(bob) == 0);
            startMeasuringGas('swap T0T1 two orders');
            pb.swap(0, orderSize * 2, bob, '');
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == orderSize * 2);
        }
        {
            uint256 expectedPayout = ((orderSize * price0) / (10**(18 + 6))) + ((orderSize * price1) / (10**(18 + 6)));
            assert(token0.balanceOf(bob) == 0);
            uint256[] memory ids = new uint256[](2);
            ids[0] = order0;
            ids[1] = order1;
            startMeasuringGas('settle two orders');
            pb.settle(bob, ids);
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == expectedPayout);
        }
        assert(pb.keyOrderIndexes(2) == 0);
        assert(pb.keyOrderIndexes(3) == 0);
        assert(pb.reserve0() == 0);
        assert(pb.reserve1() == 0);
    }

    function testFillTwoOrdersT0() public {
        uint256 price0 = 10**(18 + 6);
        uint256 price1 = price0 + (((price0 * 300) / 100000) + 1);
        uint256 orderSize = 100 ether;
        {
            token0.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(0) == 0);
            assert(pb.keyOrderIndexes(1) == 0);
            pb.open(price0, 0, bob);
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
            vm.stopPrank();
        }
        {
            token0.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
            pb.open(price1, 1, bob);
            assert(pb.keyOrderIndexes(0) == 2);
            assert(pb.keyOrderIndexes(1) == 1);
            vm.stopPrank();
        }
        {
            uint256 orderId = price0 << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 2);
            assert(order.next == 0);
            assert(order.price == price0);
            assert(order.token == 0);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
        }
        {
            uint256 orderId = price1 << 2;
            IBook.Order memory order = pb.orders(2);
            assert(order.prev == 0);
            assert(order.next == 1);
            assert(order.price == price1);
            assert(order.token == 0);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
        }
        {
            uint256 amount1In = ((orderSize * price0) / (10**(18 + 6))) + ((orderSize * price1) / (10**(18 + 6)));
            token1.mint(address(pb), amount1In);
            assert(token0.balanceOf(bob) == 0);
            startMeasuringGas('swap T1T0 two orders');
            pb.swap(orderSize * 2, 0, bob, '');
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == orderSize * 2);
        }
        {
            uint256 expectedPayout = ((orderSize * price0) / (10**(18 + 6))) + ((orderSize * price1) / (10**(18 + 6)));
            assert(token1.balanceOf(bob) == 0);
            uint256[] memory ids = new uint256[](2);
            ids[0] = price0 << 2;
            ids[1] = price1 << 2;
            startMeasuringGas('settle two orders');
            pb.settle(bob, ids);
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == expectedPayout);
        }
        assert(pb.keyOrderIndexes(0) == 0);
        assert(pb.keyOrderIndexes(1) == 0);
        assert(pb.reserve0() == 0);
        assert(pb.reserve1() == 0);
    }

    function testFillAfterNewDepositOrderT0() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;
        {
            token0.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(0) == 0);
            assert(pb.keyOrderIndexes(1) == 0);
            pb.open(price, 0, bob);
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
            vm.stopPrank();
        }
        {
            uint256 orderId = (10**(18 + 6)) << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
        }
        {
            uint256 amount1In = ((orderSize / 2) * price) / (10**(18 + 6));
            token1.mint(address(pb), amount1In);
            assert(token0.balanceOf(bob) == 0);
            startMeasuringGas('swap T1T0');
            pb.swap(orderSize / 2, 0, bob, '');
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == orderSize / 2);
        }
        {
            uint256 expectedPayout = ((orderSize / 2) * price) / (10**(18 + 6));
            assert(token1.balanceOf(bob) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = price << 2;
            startMeasuringGas('settle');
            pb.settle(bob, ids);
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == expectedPayout);
        }
        {
            uint256 orderId = (10**(18 + 6)) << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 50 ether);
            assert(order.remainingLiquidity == 50 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 1);
            assert(pb.rounds(bob, orderId) == 1);
        }
        {
            token0.mint(address(pb), orderSize);
            vm.startPrank(alice);
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
            pb.open(price, 1, alice);
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
            vm.stopPrank();
        }
        {
            uint256 orderId = (10**(18 + 6)) << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 150 ether);
            assert(order.remainingLiquidity == 150 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 1);
            assert(pb.rounds(bob, orderId) == 1);
            assert(pb.rounds(alice, orderId) == 1);
        }
        {
            vm.startPrank(bob);
            token0.transfer(address(0), token0.balanceOf(bob));
            vm.stopPrank();
        }
        {
            uint256 amount1In = ((orderSize) * price) / (10**(18 + 6));
            token1.mint(address(pb), amount1In);
            assert(token0.balanceOf(bob) == 0);
            startMeasuringGas('swap T1T0');
            pb.swap(orderSize, 0, bob, '');
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == orderSize);
        }
        {
            uint256 expectedPayout = ((((orderSize) * price) / (10**(18 + 6))) * 100 ether) / 150 ether;
            assert(token1.balanceOf(alice) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = price << 2;
            startMeasuringGas('settle');
            pb.settle(alice, ids);
            stopMeasuringGas();
            assert(token1.balanceOf(alice) == expectedPayout);
        }
        {
            uint256 orderId = (10**(18 + 6)) << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 50 ether);
            assert(order.remainingLiquidity == 16666666666666666666);
            assert(order.nextLiquidity == 33333333333333333334);
            assert(pb.orderRounds(orderId) == 1);
            assert(pb.rounds(bob, orderId) == 1);
            assert(pb.rounds(alice, orderId) == 2);
        }
    }

    function testFillAfterNewDepositOrderT1() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;
        {
            token1.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(2) == 0);
            assert(pb.keyOrderIndexes(3) == 0);
            pb.open(price, 0, bob);
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
            vm.stopPrank();
        }
        {
            uint256 orderId = ((price << 1) + 1) << 1;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
        }
        {
            uint256 amount0In = ((orderSize / 2) * price) / (10**(18 + 6));
            token0.mint(address(pb), amount0In);
            assert(token1.balanceOf(bob) == 0);
            startMeasuringGas('swap T0T1');
            pb.swap(0, orderSize / 2, bob, '');
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == orderSize / 2);
        }
        {
            uint256 expectedPayout = ((orderSize / 2) * price) / (10**(18 + 6));
            assert(token0.balanceOf(bob) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = ((price << 1) + 1) << 1;
            startMeasuringGas('settle');
            pb.settle(bob, ids);
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == expectedPayout);
        }
        {
            uint256 orderId = ((price << 1) + 1) << 1;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 50 ether);
            assert(order.remainingLiquidity == 50 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 1);
            assert(pb.rounds(bob, orderId) == 1);
        }
        {
            token1.mint(address(pb), orderSize);
            vm.startPrank(alice);
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
            pb.open(price, 1, alice);
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
            vm.stopPrank();
        }
        {
            uint256 orderId = ((price << 1) + 1) << 1;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 150 ether);
            assert(order.remainingLiquidity == 150 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 1);
            assert(pb.rounds(bob, orderId) == 1);
            assert(pb.rounds(alice, orderId) == 1);
        }
        {
            vm.startPrank(bob);
            token1.transfer(address(0), token1.balanceOf(bob));
            vm.stopPrank();
        }
        {
            uint256 amount0In = ((orderSize) * price) / (10**(18 + 6));
            token0.mint(address(pb), amount0In);
            assert(token1.balanceOf(bob) == 0);
            startMeasuringGas('swap T0T1');
            pb.swap(0, orderSize, bob, '');
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == orderSize);
        }
        {
            uint256 expectedPayout = ((((orderSize) * price) / (10**(18 + 6))) * 100 ether) / 150 ether;
            assert(token0.balanceOf(alice) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = ((price << 1) + 1) << 1;
            startMeasuringGas('settle');
            pb.settle(alice, ids);
            stopMeasuringGas();
            assert(token0.balanceOf(alice) == expectedPayout);
        }
        {
            uint256 orderId = ((price << 1) + 1) << 1;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 50 ether);
            assert(order.remainingLiquidity == 16666666666666666666);
            assert(order.nextLiquidity == 33333333333333333334);
            assert(pb.orderRounds(orderId) == 1);
            assert(pb.rounds(bob, orderId) == 1);
            assert(pb.rounds(alice, orderId) == 2);
        }
    }

    function testFillAfterNewDepositWithoutSettleOrderT0() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;
        {
            token0.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(0) == 0);
            assert(pb.keyOrderIndexes(1) == 0);
            pb.open(price, 0, bob);
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
            vm.stopPrank();
        }
        {
            uint256 orderId = (10**(18 + 6)) << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
        }
        {
            uint256 amount1In = ((orderSize / 2) * price) / (10**(18 + 6));
            token1.mint(address(pb), amount1In);
            assert(token0.balanceOf(bob) == 0);
            startMeasuringGas('swap T1T0');
            pb.swap(orderSize / 2, 0, bob, '');
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == orderSize / 2);
        }
        {
            uint256 orderId = (10**(18 + 6)) << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 50 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
        }
        {
            token0.mint(address(pb), orderSize);
            vm.startPrank(alice);
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
            pb.open(price, 1, alice);
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
            vm.stopPrank();
        }
        {
            uint256 orderId = (10**(18 + 6)) << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 50 ether);
            assert(order.nextLiquidity == 100 ether);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
            assert(pb.rounds(alice, orderId) == 1);
        }
        {
            vm.startPrank(bob);
            token0.transfer(address(0), token0.balanceOf(bob));
            vm.stopPrank();
        }
        {
            uint256 amount1In = ((orderSize) * price) / (10**(18 + 6));
            token1.mint(address(pb), amount1In);
            assert(token0.balanceOf(bob) == 0);
            startMeasuringGas('swap T1T0');
            pb.swap(orderSize, 0, bob, '');
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == orderSize);
        }
        {
            uint256 expectedPayout = (orderSize * price) / (10**(18 + 6));
            assert(token1.balanceOf(bob) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = price << 2;
            startMeasuringGas('settle');
            pb.settle(bob, ids);
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == expectedPayout);
        }
        {
            uint256 expectedPayout = ((orderSize / 2) * price) / (10**(18 + 6));
            assert(token1.balanceOf(alice) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = price << 2;
            startMeasuringGas('settle');
            pb.settle(alice, ids);
            stopMeasuringGas();
            assert(token1.balanceOf(alice) == expectedPayout);
        }
        {
            uint256 orderId = (10**(18 + 6)) << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 50 ether);
            assert(order.remainingLiquidity == 50 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 2);
            assert(pb.rounds(bob, orderId) == 0);
            assert(pb.rounds(alice, orderId) == 2);
        }
    }

    function testFillAfterNewDepositWithoutSettleOrderT1() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;
        {
            token1.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(2) == 0);
            assert(pb.keyOrderIndexes(3) == 0);
            pb.open(price, 0, bob);
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
            vm.stopPrank();
        }
        {
            uint256 orderId = ((price << 1) + 1) << 1;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
        }
        {
            uint256 amount0In = ((orderSize / 2) * price) / (10**(18 + 6));
            token0.mint(address(pb), amount0In);
            assert(token1.balanceOf(bob) == 0);
            startMeasuringGas('swap T0T1');
            pb.swap(0, orderSize / 2, bob, '');
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == orderSize / 2);
        }
        {
            uint256 orderId = ((price << 1) + 1) << 1;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 50 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
        }
        {
            token1.mint(address(pb), orderSize);
            vm.startPrank(alice);
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
            pb.open(price, 1, alice);
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
            vm.stopPrank();
        }
        {
            uint256 orderId = ((price << 1) + 1) << 1;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 50 ether);
            assert(order.nextLiquidity == 100 ether);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
            assert(pb.rounds(alice, orderId) == 1);
        }
        {
            vm.startPrank(bob);
            token1.transfer(address(0), token1.balanceOf(bob));
            vm.stopPrank();
        }
        {
            uint256 amount0In = ((orderSize) * price) / (10**(18 + 6));
            token0.mint(address(pb), amount0In);
            assert(token1.balanceOf(bob) == 0);
            startMeasuringGas('swap T0T1');
            pb.swap(0, orderSize, bob, '');
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == orderSize);
        }
        {
            uint256 expectedPayout = (orderSize * price) / (10**(18 + 6));
            assert(token0.balanceOf(bob) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = ((price << 1) + 1) << 1;
            startMeasuringGas('settle');
            pb.settle(bob, ids);
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == expectedPayout);
        }
        {
            uint256 expectedPayout = ((orderSize / 2) * price) / (10**(18 + 6));
            assert(token0.balanceOf(alice) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = ((price << 1) + 1) << 1;
            startMeasuringGas('settle');
            pb.settle(alice, ids);
            stopMeasuringGas();
            assert(token0.balanceOf(alice) == expectedPayout);
        }
        {
            uint256 orderId = ((price << 1) + 1) << 1;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 50 ether);
            assert(order.remainingLiquidity == 50 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 2);
            assert(pb.rounds(bob, orderId) == 0);
            assert(pb.rounds(alice, orderId) == 2);
        }
    }

    function testFillHalfOrderT0() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;
        {
            token0.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(0) == 0);
            assert(pb.keyOrderIndexes(1) == 0);
            pb.open(price, 0, bob);
            assert(pb.keyOrderIndexes(0) == 1);
            assert(pb.keyOrderIndexes(1) == 1);
        }
        {
            uint256 orderId = (10**(18 + 6)) << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
        }
        {
            uint256 amount1In = ((orderSize / 2) * price) / (10**(18 + 6));
            token1.mint(address(pb), amount1In);
            assert(token0.balanceOf(bob) == 0);
            startMeasuringGas('swap T1T0');
            pb.swap(orderSize / 2, 0, bob, '');
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == orderSize / 2);
        }
        {
            address[] memory owners = new address[](2);
            uint256[] memory ids = new uint256[](2);

            owners[0] = bob;
            owners[1] = bob;

            ids[0] = price << 2;
            ids[1] = ids[0] + 1;

            uint256[] memory balances = pb.balanceOfBatch(owners, ids);

            assert(balances[0] == orderSize - (orderSize / 2));
            assert(balances[1] == ((orderSize / 2) * price) / (10**(18 + 6)));
        }
        {
            uint256 expectedPayout = ((orderSize / 2) * price) / (10**(18 + 6));
            assert(token1.balanceOf(bob) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = price << 2;
            startMeasuringGas('settle');
            pb.settle(bob, ids);
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == expectedPayout);
        }
        {
            address[] memory owners = new address[](2);
            uint256[] memory ids = new uint256[](2);

            owners[0] = bob;
            owners[1] = bob;

            ids[0] = price << 2;
            ids[1] = ids[0] + 1;

            uint256[] memory balances = pb.balanceOfBatch(owners, ids);

            assert(balances[0] == orderSize - (orderSize / 2));
            assert(balances[1] == 0);
        }
        {
            uint256 orderId = (10**(18 + 6)) << 2;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 0);
            assert(order.liquidity == 50 ether);
            assert(order.remainingLiquidity == 50 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 1);
            assert(pb.rounds(bob, orderId) == 1);
        }
    }

    function testFillHalfOrderT1() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;
        {
            token1.mint(address(pb), orderSize);
            vm.startPrank(bob);
            assert(pb.keyOrderIndexes(2) == 0);
            assert(pb.keyOrderIndexes(3) == 0);
            pb.open(price, 0, bob);
            assert(pb.keyOrderIndexes(2) == 1);
            assert(pb.keyOrderIndexes(3) == 1);
        }
        {
            uint256 orderId = (((10**(18 + 6)) << 1) + 1) << 1;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 100 ether);
            assert(order.remainingLiquidity == 100 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 0);
            assert(pb.rounds(bob, orderId) == 0);
        }
        {
            uint256 amount0In = ((orderSize / 2) * price) / (10**(18 + 6));
            token0.mint(address(pb), amount0In);
            assert(token1.balanceOf(bob) == 0);
            startMeasuringGas('swap T0T1');
            pb.swap(0, orderSize / 2, bob, '');
            stopMeasuringGas();
            assert(token1.balanceOf(bob) == orderSize / 2);
        }
        {
            address[] memory owners = new address[](2);
            uint256[] memory ids = new uint256[](2);

            owners[0] = bob;
            owners[1] = bob;

            ids[0] = ((price << 1) + 1) << 1;
            ids[1] = ids[0] + 1;

            uint256[] memory balances = pb.balanceOfBatch(owners, ids);

            assert(balances[0] == orderSize - (orderSize / 2));
            assert(balances[1] == ((orderSize / 2) * price) / (10**(18 + 6)));
        }
        {
            uint256 expectedPayout = ((orderSize / 2) * price) / (10**(18 + 6));
            assert(token0.balanceOf(bob) == 0);
            uint256[] memory ids = new uint256[](1);
            ids[0] = ((price << 1) + 1) << 1;
            startMeasuringGas('settle');
            pb.settle(bob, ids);
            stopMeasuringGas();
            assert(token0.balanceOf(bob) == expectedPayout);
        }
        {
            address[] memory owners = new address[](2);
            uint256[] memory ids = new uint256[](2);

            owners[0] = bob;
            owners[1] = bob;

            ids[0] = ((price << 1) + 1) << 1;
            ids[1] = ids[0] + 1;

            uint256[] memory balances = pb.balanceOfBatch(owners, ids);

            assert(balances[0] == orderSize - (orderSize / 2));
            assert(balances[1] == 0);
        }
        {
            uint256 orderId = (((10**(18 + 6)) << 1) + 1) << 1;
            IBook.Order memory order = pb.orders(1);
            assert(order.prev == 0);
            assert(order.next == 0);
            assert(order.price == 10**(18 + 6));
            assert(order.token == 1);
            assert(order.liquidity == 50 ether);
            assert(order.remainingLiquidity == 50 ether);
            assert(order.nextLiquidity == 0);
            assert(pb.orderRounds(orderId) == 1);
            assert(pb.rounds(bob, orderId) == 1);
        }
    }

    function testOpenAndClose100OrdersT0() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;

        for (uint256 i; i < 100; ++i) {
            token0.mint(address(pb), orderSize);
            pb.open(price, uint64(i), bob);

            IBook.Order memory order = pb.orders(uint64(i + 1));
            assert(order.prev == 0);
            assert(order.next == i);
            assert(order.price == price);
            assert(order.token == 0);
            assert(order.liquidity == orderSize);
            assert(order.remainingLiquidity == orderSize);
            assert(order.nextLiquidity == 0);

            assert(pb.balanceOf(bob, price << 2) == orderSize);

            price += ((price * 300) / 100000) + 1;
        }

        price = 10**(18 + 6);

        for (uint256 i; i < 100; ++i) {
            vm.startPrank(bob);
            pb.safeTransferFrom(bob, address(pb), price << 2, pb.balanceOf(bob, price << 2), '');
            vm.stopPrank();

            assert(token0.balanceOf(bob) == 0);

            pb.close(price << 2, bob);

            assert(token0.balanceOf(bob) == orderSize);

            vm.startPrank(bob);
            token0.transfer(address(0), orderSize);
            vm.stopPrank();

            price += ((price * 300) / 100000) + 1;
        }

        assert(pb.keyOrderIndexes(0) == 0);
        assert(pb.keyOrderIndexes(1) == 0);
        assert(pb.reserve0() == 0);
    }

    function testOpenAndClose100OrdersT1() public {
        uint256 price = 10**(18 + 6);
        uint256 orderSize = 100 ether;

        for (uint256 i; i < 100; ++i) {
            token1.mint(address(pb), orderSize);
            pb.open(price, uint64(i), bob);

            IBook.Order memory order = pb.orders(uint64(i + 1));
            assert(order.prev == 0);
            assert(order.next == i);
            assert(order.price == price);
            assert(order.token == 1);
            assert(order.liquidity == orderSize);
            assert(order.remainingLiquidity == orderSize);
            assert(order.nextLiquidity == 0);

            assert(pb.balanceOf(bob, ((price << 1) + 1) << 1) == orderSize);

            price += ((price * 300) / 100000) + 1;
        }

        price = 10**(18 + 6);

        for (uint256 i; i < 100; ++i) {
            vm.startPrank(bob);
            pb.safeTransferFrom(
                bob,
                address(pb),
                ((price << 1) + 1) << 1,
                pb.balanceOf(bob, ((price << 1) + 1) << 1),
                ''
            );
            vm.stopPrank();

            assert(token1.balanceOf(bob) == 0);

            pb.close(((price << 1) + 1) << 1, bob);

            assert(token1.balanceOf(bob) == orderSize);

            vm.startPrank(bob);
            token1.transfer(address(0), orderSize);
            vm.stopPrank();

            price += ((price * 300) / 100000) + 1;
        }

        assert(pb.keyOrderIndexes(2) == 0);
        assert(pb.keyOrderIndexes(3) == 0);
        assert(pb.reserve1() == 0);
    }
}

// contract PairBookFuzz is DSTest {
//     function setUp() public {}

//     function testExample(address) public {
//         assertTrue(true);
//     }
// }
