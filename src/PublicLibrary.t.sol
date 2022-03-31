// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import 'solmate/test/utils/DSTestPlus.sol';
import 'solmate/tokens/ERC1155.sol';
import 'solmate/tokens/ERC20.sol';
import 'forge-std/Vm.sol';

import './test/console.sol';

import './Printer.sol';
import './PublicLibrary.sol';

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

contract ERC1155Mock is ERC1155 {
    function uri(uint256) public pure override returns (string memory) {
        return '';
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount
    ) external {
        _mint(to, id, amount, '');
    }

    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external {
        _burn(from, id, amount);
    }
}

contract PublicLibraryERC20ToERC20Test is DSTestPlus {
    Vm public constant vm = Vm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    Printer internal printer;
    PublicLibrary internal publicLibrary;
    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;
    ERC20Mock internal tokenC;
    Book internal book;
    bool internal tokenAisZero;

    address internal bob = address(1);
    address internal alice = address(2);

    function setUp() public {
        printer = new Printer();
        tokenA = new ERC20Mock('US Dollar', 'USDC', 18);
        tokenB = new ERC20Mock('Wrapped Ether', 'WETH', 18);
        tokenC = new ERC20Mock('Dai Stablecoin', 'DAI', 18);
        book = Book(printer.createERC20Book(address(tokenA), address(tokenB)));
        printer.createERC20Book(address(tokenB), address(tokenC));
        publicLibrary = new PublicLibrary(address(printer));
        tokenAisZero = book.token0() == address(tokenA);
    }

    function testGetAmountOutInsufficientLiqAB() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                'InsufficientLiquidity(address,uint8,uint256)',
                address(book),
                tokenAisZero ? 1 : 0,
                1 ether
            )
        );
        publicLibrary.getERC20ToERC20AmountOut(address(tokenA), address(tokenB), 1 ether);
    }

    function testGetAmountOutInsufficientLiqBA() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                'InsufficientLiquidity(address,uint8,uint256)',
                address(book),
                tokenAisZero ? 0 : 1,
                1 ether
            )
        );
        publicLibrary.getERC20ToERC20AmountOut(address(tokenB), address(tokenA), 1 ether);
    }

    function testGetAmountOutSingleOrderAB() public {
        uint256 sellPrice = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellSize = 1 ether;
        uint256 buySize = 2000 ether;
        tokenB.mint(address(bob), sellSize);
        vm.startPrank(bob);
        tokenB.approve(address(publicLibrary), sellSize);
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenA), address(tokenB), sellPrice, sellSize, 0);
        stopMeasuringGas();
        vm.stopPrank();
        uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenA), address(tokenB), buySize);
        assert(amountOut == sellSize);
    }

    function testGetAmountOutSingleOrderBA() public {
        uint256 sellPrice = (10**36) * 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellSize = 2000 ether;
        uint256 buySize = 1 ether;
        tokenA.mint(address(bob), sellSize);
        vm.startPrank(bob);
        tokenA.approve(address(publicLibrary), sellSize);
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenB), address(tokenA), sellPrice, sellSize, 0);
        stopMeasuringGas();
        vm.stopPrank();
        uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenB), address(tokenA), buySize);
        assert(amountOut == sellSize);
    }

    function testGetAmountOutMultiOrderAB() public {
        uint256 sellPriceOne = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellPriceTwo = (10**36) / uint256(4000); // Read as => buy 1 USDC for 1/4000 ETH
        uint256 sellSize = 1 ether;
        uint256 buySize = ((sellSize / 2) * (10**36)) / sellPriceOne + ((sellSize / 2) * (10**36)) / sellPriceTwo;
        tokenB.mint(address(bob), sellSize);
        vm.startPrank(bob);
        tokenB.approve(address(publicLibrary), sellSize);
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenA), address(tokenB), sellPriceOne, sellSize / 2, 0);
        stopMeasuringGas();
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenA), address(tokenB), sellPriceTwo, sellSize / 2, 0);
        stopMeasuringGas();
        vm.stopPrank();
        uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenA), address(tokenB), buySize);
        assert(amountOut == sellSize);
    }

    function testGetAmountOutMultiOrderBA() public {
        uint256 sellPriceOne = (10**36) * 2000; // Read as => buy 1 ETH for 2000 ETH
        uint256 sellPriceTwo = (10**36) * uint256(4000); // Read as => buy 1 ETH for 4000 USDC
        uint256 sellSize = 3000 ether;
        uint256 buySize = ((sellSize / 2) * (10**36)) / sellPriceOne + ((sellSize / 2) * (10**36)) / sellPriceTwo;
        tokenA.mint(address(bob), sellSize);
        vm.startPrank(bob);
        tokenA.approve(address(publicLibrary), sellSize);
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenB), address(tokenA), sellPriceOne, sellSize / 2, 0);
        stopMeasuringGas();
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenB), address(tokenA), sellPriceTwo, sellSize / 2, 1);
        stopMeasuringGas();
        vm.stopPrank();
        uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenB), address(tokenA), buySize);
        assert(amountOut == sellSize);
    }

    function testGetAmountInInsufficientLiqAB() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                'InsufficientLiquidity(address,uint8,uint256)',
                address(book),
                tokenAisZero ? 1 : 0,
                1 ether
            )
        );
        publicLibrary.getERC20ToERC20AmountIn(address(tokenA), address(tokenB), 1 ether);
    }

    function testGetAmountInInsufficientLiqBA() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                'InsufficientLiquidity(address,uint8,uint256)',
                address(book),
                tokenAisZero ? 0 : 1,
                1 ether
            )
        );
        publicLibrary.getERC20ToERC20AmountIn(address(tokenB), address(tokenA), 1 ether);
    }

    function testGetAmountInSingleOrderAB() public {
        uint256 sellPrice = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellSize = 1 ether;
        uint256 buySize = 2000 ether;
        tokenB.mint(address(bob), sellSize);
        vm.startPrank(bob);
        tokenB.approve(address(publicLibrary), sellSize);
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenA), address(tokenB), sellPrice, sellSize, 0);
        stopMeasuringGas();
        vm.stopPrank();
        uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenA), address(tokenB), sellSize);
        assert(amountIn == buySize);
    }

    function testGetAmountInSingleOrderBA() public {
        uint256 sellPrice = (10**36) * 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellSize = 2000 ether;
        uint256 buySize = 1 ether;
        tokenA.mint(address(bob), sellSize);
        vm.startPrank(bob);
        tokenA.approve(address(publicLibrary), sellSize);
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenB), address(tokenA), sellPrice, sellSize, 0);
        stopMeasuringGas();
        vm.stopPrank();
        uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenB), address(tokenA), sellSize);
        assert(amountIn == buySize);
    }

    function testGetAmountInMultiOrderAB() public {
        uint256 sellPriceOne = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellPriceTwo = (10**36) / uint256(4000); // Read as => buy 1 USDC for 1/4000 ETH
        uint256 sellSize = 1 ether;
        uint256 buySize = ((sellSize / 2) * (10**36)) / sellPriceOne + ((sellSize / 2) * (10**36)) / sellPriceTwo;
        tokenB.mint(address(bob), sellSize);
        vm.startPrank(bob);
        tokenB.approve(address(publicLibrary), sellSize);
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenA), address(tokenB), sellPriceOne, sellSize / 2, 0);
        stopMeasuringGas();
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenA), address(tokenB), sellPriceTwo, sellSize / 2, 0);
        stopMeasuringGas();
        vm.stopPrank();
        uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenA), address(tokenB), sellSize);
        assert(amountIn == buySize);
    }

    function testGetAmountInMultiOrderBA() public {
        uint256 sellPriceOne = (10**36) * 2000; // Read as => buy 1 ETH for 2000 ETH
        uint256 sellPriceTwo = (10**36) * uint256(4000); // Read as => buy 1 ETH for 4000 USDC
        uint256 sellSize = 3000 ether;
        uint256 buySize = ((sellSize / 2) * (10**36)) / sellPriceOne + ((sellSize / 2) * (10**36)) / sellPriceTwo;
        tokenA.mint(address(bob), sellSize);
        vm.startPrank(bob);
        tokenA.approve(address(publicLibrary), sellSize);
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenB), address(tokenA), sellPriceOne, sellSize / 2, 0);
        stopMeasuringGas();
        startMeasuringGas('openERC20ToERC20Order');
        publicLibrary.openERC20ToERC20Order(address(tokenB), address(tokenA), sellPriceTwo, sellSize / 2, 1);
        stopMeasuringGas();
        vm.stopPrank();
        uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenB), address(tokenA), sellSize);
        assert(amountIn == buySize);
    }

    function testSwapE20to20AB() public {
        uint256 sellPrice = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellSize = 1 ether;
        uint256 buySize = 2000 ether;
        uint256 orderId;
        {
            tokenB.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderId) = publicLibrary.openERC20ToERC20Order(address(tokenA), address(tokenB), sellPrice, sellSize, 0);
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenA), address(tokenB), buySize);
            tokenA.mint(address(alice), buySize);
            vm.startPrank(alice);
            tokenA.approve(address(publicLibrary), buySize);
            startMeasuringGas('swapExactERC20forERC20');
            publicLibrary.swapExactERC20forERC20(
                buySize,
                amountOut,
                address(tokenA),
                address(tokenB),
                alice,
                block.timestamp
            );
            stopMeasuringGas();
            vm.stopPrank();
            assert(tokenB.balanceOf(alice) == amountOut);
        }
        {
            vm.startPrank(bob);
            address[] memory books = new address[](1);
            books[0] = address(book);
            uint256[] memory idCounts = new uint256[](1);
            idCounts[0] = 1;
            uint256[] memory ids = new uint256[](1);
            ids[0] = orderId;
            publicLibrary.settle(books, idCounts, ids, bob);
            vm.stopPrank();
            assert(tokenA.balanceOf(bob) == buySize);
        }
    }

    function testSwapE20to20FailAB() public {
        uint256 sellPrice = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellSize = 1 ether;
        uint256 buySize = 2000 ether;
        uint256 orderId;
        {
            tokenB.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderId) = publicLibrary.openERC20ToERC20Order(address(tokenA), address(tokenB), sellPrice, sellSize, 0);
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenA), address(tokenB), buySize);
            tokenA.mint(address(alice), buySize);
            vm.startPrank(alice);
            tokenA.approve(address(publicLibrary), buySize - 1);
            vm.expectRevert(abi.encodeWithSignature('AmountOutTooLow(uint256)', 999999999999999999));
            publicLibrary.swapExactERC20forERC20(
                buySize - 1,
                amountOut,
                address(tokenA),
                address(tokenB),
                alice,
                block.timestamp
            );
        }
    }

    function testSwapE20to20MultiOrderAB() public {
        uint256 sellPriceOne = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellPriceTwo = (10**36) / uint256(4000); // Read as => buy 1 USDC for 1/4000 ETH
        uint256 sellSize = 1 ether;
        uint256 buySize = ((sellSize / 2) * (10**36)) / sellPriceOne + ((sellSize / 2) * (10**36)) / sellPriceTwo;
        uint256 orderIdOne;
        uint256 orderIdTwo;
        {
            tokenB.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdOne) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceOne,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdTwo) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceTwo,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenA), address(tokenB), buySize);
            tokenA.mint(address(alice), buySize);
            vm.startPrank(alice);
            tokenA.approve(address(publicLibrary), buySize);
            startMeasuringGas('swapExactERC20forERC20');
            publicLibrary.swapExactERC20forERC20(
                buySize,
                amountOut,
                address(tokenA),
                address(tokenB),
                alice,
                block.timestamp
            );
            stopMeasuringGas();
            vm.stopPrank();
            assert(tokenB.balanceOf(alice) == amountOut);
        }
        {
            vm.startPrank(bob);
            address[] memory books = new address[](1);
            books[0] = address(book);
            uint256[] memory idCounts = new uint256[](1);
            idCounts[0] = 2;
            uint256[] memory ids = new uint256[](2);
            ids[0] = orderIdOne;
            ids[1] = orderIdTwo;
            publicLibrary.settle(books, idCounts, ids, bob);
            vm.stopPrank();
            assert(tokenA.balanceOf(bob) == buySize);
        }
    }

    function testSwapE20to20MultiOrderABFail() public {
        uint256 sellPriceOne = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellPriceTwo = (10**36) / uint256(4000); // Read as => buy 1 USDC for 1/4000 ETH
        uint256 sellSize = 1 ether;
        uint256 buySize = ((sellSize / 2) * (10**36)) / sellPriceOne + ((sellSize / 2) * (10**36)) / sellPriceTwo;
        uint256 orderIdOne;
        uint256 orderIdTwo;
        {
            tokenB.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdOne) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceOne,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdTwo) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceTwo,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenA), address(tokenB), buySize);
            tokenA.mint(address(alice), buySize);
            vm.startPrank(alice);
            tokenA.approve(address(publicLibrary), buySize - 1);
            vm.expectRevert(abi.encodeWithSignature('AmountOutTooLow(uint256)', 999999999999999999));
            publicLibrary.swapExactERC20forERC20(
                buySize - 1,
                amountOut,
                address(tokenA),
                address(tokenB),
                alice,
                block.timestamp
            );
        }
    }

    function testSwapE20to20BA() public {
        uint256 sellPrice = (10**36) * 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellSize = 2000 ether;
        uint256 buySize = 1 ether;
        uint256 orderId;
        {
            tokenA.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderId) = publicLibrary.openERC20ToERC20Order(address(tokenB), address(tokenA), sellPrice, sellSize, 0);
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenB), address(tokenA), buySize);
            tokenB.mint(address(alice), buySize);
            vm.startPrank(alice);
            tokenB.approve(address(publicLibrary), buySize);
            startMeasuringGas('swapExactERC20forERC20');
            publicLibrary.swapExactERC20forERC20(
                buySize,
                amountOut,
                address(tokenB),
                address(tokenA),
                alice,
                block.timestamp
            );
            stopMeasuringGas();
            vm.stopPrank();
            assert(tokenA.balanceOf(alice) == amountOut);
        }
        {
            vm.startPrank(bob);
            address[] memory books = new address[](1);
            books[0] = address(book);
            uint256[] memory idCounts = new uint256[](1);
            idCounts[0] = 1;
            uint256[] memory ids = new uint256[](1);
            ids[0] = orderId;
            publicLibrary.settle(books, idCounts, ids, bob);
            vm.stopPrank();
            assert(tokenB.balanceOf(bob) == buySize);
        }
    }

    function testSwapE20to20FailBA() public {
        uint256 sellPrice = (10**36) * 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellSize = 2000 ether;
        uint256 buySize = 1 ether;
        uint256 orderId;
        {
            tokenA.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderId) = publicLibrary.openERC20ToERC20Order(address(tokenB), address(tokenA), sellPrice, sellSize, 0);
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenB), address(tokenA), buySize);
            tokenB.mint(address(alice), buySize);
            vm.startPrank(alice);
            tokenB.approve(address(publicLibrary), buySize - 1);
            vm.expectRevert(abi.encodeWithSignature('AmountOutTooLow(uint256)', 1999999999999999998000));
            publicLibrary.swapExactERC20forERC20(
                buySize - 1,
                amountOut,
                address(tokenB),
                address(tokenA),
                alice,
                block.timestamp
            );
        }
    }

    function testSwapE20to20MultiOrderBA() public {
        uint256 sellPriceOne = (10**36) * 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellPriceTwo = (10**36) * uint256(4000); // Read as => buy 1 ETH for 4000 USDC
        uint256 sellSize = 2000 ether;
        uint256 buySize = ((sellSize / 2) * (10**36)) / sellPriceOne + ((sellSize / 2) * (10**36)) / sellPriceTwo;
        uint256 orderIdOne;
        uint256 orderIdTwo;
        {
            tokenA.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdOne) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenA),
                sellPriceOne,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdTwo) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenA),
                sellPriceTwo,
                sellSize / 2,
                1
            );
            stopMeasuringGas();
            vm.stopPrank();
        }

        {
            uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenB), address(tokenA), buySize);
            tokenB.mint(address(alice), buySize);
            vm.startPrank(alice);
            tokenB.approve(address(publicLibrary), buySize);
            startMeasuringGas('swapExactERC20forERC20');
            publicLibrary.swapExactERC20forERC20(
                buySize,
                amountOut,
                address(tokenB),
                address(tokenA),
                alice,
                block.timestamp
            );
            stopMeasuringGas();
            vm.stopPrank();
            assert(tokenA.balanceOf(alice) == amountOut);
        }
        {
            vm.startPrank(bob);
            address[] memory books = new address[](1);
            books[0] = address(book);
            uint256[] memory idCounts = new uint256[](1);
            idCounts[0] = 2;
            uint256[] memory ids = new uint256[](2);
            ids[0] = orderIdOne;
            ids[1] = orderIdTwo;
            publicLibrary.settle(books, idCounts, ids, bob);
            vm.stopPrank();
            assert(tokenB.balanceOf(bob) == buySize);
        }
    }

    function testSwapE20to20MultiOrderBAFail() public {
        uint256 sellPriceOne = (10**36) * 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellPriceTwo = (10**36) * uint256(4000); // Read as => buy 1 ETH for 4000 USDC
        uint256 sellSize = 2000 ether;
        uint256 buySize = ((sellSize / 2) * (10**36)) / sellPriceOne + ((sellSize / 2) * (10**36)) / sellPriceTwo;
        uint256 orderIdOne;
        uint256 orderIdTwo;
        {
            tokenA.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdOne) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenA),
                sellPriceOne,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdTwo) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenA),
                sellPriceTwo,
                sellSize / 2,
                1
            );
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountOut = publicLibrary.getERC20ToERC20AmountOut(address(tokenB), address(tokenA), buySize);
            tokenB.mint(address(alice), buySize);
            vm.startPrank(alice);
            tokenB.approve(address(publicLibrary), buySize - 1);
            vm.expectRevert(abi.encodeWithSignature('AmountOutTooLow(uint256)', 1999999999999999998000));
            publicLibrary.swapExactERC20forERC20(
                buySize - 1,
                amountOut,
                address(tokenB),
                address(tokenA),
                alice,
                block.timestamp
            );
        }
    }

    function testSwap20toE20AB() public {
        uint256 sellPrice = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellSize = 1 ether;
        uint256 buySize = 2000 ether;
        uint256 orderId;
        {
            tokenB.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderId) = publicLibrary.openERC20ToERC20Order(address(tokenA), address(tokenB), sellPrice, sellSize, 0);
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenA), address(tokenB), sellSize);
            tokenA.mint(address(alice), amountIn);
            vm.startPrank(alice);
            tokenA.approve(address(publicLibrary), amountIn);
            startMeasuringGas('swapERC20forExactERC20');
            publicLibrary.swapERC20forExactERC20(
                sellSize,
                amountIn,
                address(tokenA),
                address(tokenB),
                alice,
                block.timestamp
            );
            stopMeasuringGas();
            vm.stopPrank();
            assert(tokenB.balanceOf(alice) == sellSize);
        }
        {
            vm.startPrank(bob);
            address[] memory books = new address[](1);
            books[0] = address(book);
            uint256[] memory idCounts = new uint256[](1);
            idCounts[0] = 1;
            uint256[] memory ids = new uint256[](1);
            ids[0] = orderId;
            publicLibrary.settle(books, idCounts, ids, bob);
            vm.stopPrank();
            assert(tokenA.balanceOf(bob) == buySize);
        }
    }

    function testSwap20toE20FailAB() public {
        uint256 sellPrice = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellSize = 1 ether;
        uint256 orderId;
        {
            tokenB.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderId) = publicLibrary.openERC20ToERC20Order(address(tokenA), address(tokenB), sellPrice, sellSize, 0);
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenA), address(tokenB), sellSize);
            tokenA.mint(address(alice), amountIn);
            vm.startPrank(alice);
            tokenA.approve(address(publicLibrary), amountIn);
            vm.expectRevert(abi.encodeWithSignature('AmountInTooHigh(uint256)', 2000000000000000000000));
            publicLibrary.swapERC20forExactERC20(
                sellSize,
                amountIn - 1,
                address(tokenA),
                address(tokenB),
                alice,
                block.timestamp
            );
        }
    }

    function testSwap20toE20MultiOrderAB() public {
        uint256 sellPriceOne = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellPriceTwo = (10**36) / uint256(4000); // Read as => buy 1 USDC for 1/4000 ETH
        uint256 sellSize = 1 ether;
        uint256 buySize = ((sellSize / 2) * (10**36)) / sellPriceOne + ((sellSize / 2) * (10**36)) / sellPriceTwo;
        uint256 orderIdOne;
        uint256 orderIdTwo;
        {
            tokenB.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdOne) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceOne,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdTwo) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceTwo,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenA), address(tokenB), sellSize);
            tokenA.mint(address(alice), amountIn);
            vm.startPrank(alice);
            tokenA.approve(address(publicLibrary), amountIn);
            startMeasuringGas('swapERC20forExactERC20');
            publicLibrary.swapERC20forExactERC20(
                sellSize,
                amountIn,
                address(tokenA),
                address(tokenB),
                alice,
                block.timestamp
            );
            stopMeasuringGas();
            vm.stopPrank();
            assert(tokenB.balanceOf(alice) == sellSize);
        }
        {
            vm.startPrank(bob);
            address[] memory books = new address[](1);
            books[0] = address(book);
            uint256[] memory idCounts = new uint256[](1);
            idCounts[0] = 2;
            uint256[] memory ids = new uint256[](2);
            ids[0] = orderIdOne;
            ids[1] = orderIdTwo;
            publicLibrary.settle(books, idCounts, ids, bob);
            vm.stopPrank();
            assert(tokenA.balanceOf(bob) == buySize);
        }
    }

    function testSwap20toE20MultiOrderABFail() public {
        uint256 sellPriceOne = (10**36) / 2000; // Read as => buy 1 USDC for 1/2000 ETH
        uint256 sellPriceTwo = (10**36) / uint256(4000); // Read as => buy 1 USDC for 1/4000 ETH
        uint256 sellSize = 1 ether;
        uint256 orderIdOne;
        uint256 orderIdTwo;
        {
            tokenB.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdOne) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceOne,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdTwo) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceTwo,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenA), address(tokenB), sellSize);
            tokenA.mint(address(alice), amountIn);
            vm.startPrank(alice);
            tokenA.approve(address(publicLibrary), amountIn);
            vm.expectRevert(abi.encodeWithSignature('AmountInTooHigh(uint256)', 3000000000000000000000));
            publicLibrary.swapERC20forExactERC20(
                sellSize,
                amountIn - 1,
                address(tokenA),
                address(tokenB),
                alice,
                block.timestamp
            );
        }
    }

    function testSwap20toE20BA() public {
        uint256 sellPrice = (10**36) * 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellSize = 2000 ether;
        uint256 buySize = 1 ether;
        uint256 orderId;
        {
            tokenA.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderId) = publicLibrary.openERC20ToERC20Order(address(tokenB), address(tokenA), sellPrice, sellSize, 0);
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenB), address(tokenA), sellSize);
            tokenB.mint(address(alice), amountIn);
            vm.startPrank(alice);
            tokenB.approve(address(publicLibrary), amountIn);
            startMeasuringGas('swapERC20forExactERC20');
            publicLibrary.swapERC20forExactERC20(
                sellSize,
                amountIn,
                address(tokenB),
                address(tokenA),
                alice,
                block.timestamp
            );
            stopMeasuringGas();
            vm.stopPrank();
            assert(tokenA.balanceOf(alice) == sellSize);
        }
        {
            vm.startPrank(bob);
            address[] memory books = new address[](1);
            books[0] = address(book);
            uint256[] memory idCounts = new uint256[](1);
            idCounts[0] = 1;
            uint256[] memory ids = new uint256[](1);
            ids[0] = orderId;
            publicLibrary.settle(books, idCounts, ids, bob);
            vm.stopPrank();
            assert(tokenB.balanceOf(bob) == buySize);
        }
    }

    function testSwap20toE20FailBA() public {
        uint256 sellPrice = (10**36) * 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellSize = 2000 ether;
        uint256 orderId;
        {
            tokenA.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderId) = publicLibrary.openERC20ToERC20Order(address(tokenB), address(tokenA), sellPrice, sellSize, 0);
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenB), address(tokenA), sellSize);
            tokenB.mint(address(alice), amountIn);
            vm.startPrank(alice);
            tokenB.approve(address(publicLibrary), amountIn - 1);
            vm.expectRevert(abi.encodeWithSignature('AmountInTooHigh(uint256)', 1000000000000000000));
            publicLibrary.swapERC20forExactERC20(
                sellSize,
                amountIn - 1,
                address(tokenB),
                address(tokenA),
                alice,
                block.timestamp
            );
        }
    }

    function testSwap20toE20MultiOrderBA() public {
        uint256 sellPriceOne = (10**36) * 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellPriceTwo = (10**36) * uint256(4000); // Read as => buy 1 ETH for 4000 USDC
        uint256 sellSize = 2000 ether;
        uint256 buySize = ((sellSize / 2) * (10**36)) / sellPriceOne + ((sellSize / 2) * (10**36)) / sellPriceTwo;
        uint256 orderIdOne;
        uint256 orderIdTwo;
        {
            tokenA.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdOne) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenA),
                sellPriceOne,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdTwo) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenA),
                sellPriceTwo,
                sellSize / 2,
                1
            );
            stopMeasuringGas();
            vm.stopPrank();
        }

        {
            uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenB), address(tokenA), sellSize);
            tokenB.mint(address(alice), amountIn);
            vm.startPrank(alice);
            tokenB.approve(address(publicLibrary), amountIn);
            startMeasuringGas('swapERC20forExactERC20');
            publicLibrary.swapERC20forExactERC20(
                sellSize,
                amountIn,
                address(tokenB),
                address(tokenA),
                alice,
                block.timestamp
            );
            stopMeasuringGas();
            vm.stopPrank();
            assert(tokenA.balanceOf(alice) == sellSize);
        }
        {
            vm.startPrank(bob);
            address[] memory books = new address[](1);
            books[0] = address(book);
            uint256[] memory idCounts = new uint256[](1);
            idCounts[0] = 2;
            uint256[] memory ids = new uint256[](2);
            ids[0] = orderIdOne;
            ids[1] = orderIdTwo;
            publicLibrary.settle(books, idCounts, ids, bob);
            vm.stopPrank();
            assert(tokenB.balanceOf(bob) == buySize);
        }
    }

    function testSwap20toE20MultiOrderBAFail() public {
        uint256 sellPriceOne = (10**36) * 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellPriceTwo = (10**36) * uint256(4000); // Read as => buy 1 ETH for 4000 USDC
        uint256 sellSize = 2000 ether;
        uint256 orderIdOne;
        uint256 orderIdTwo;
        {
            tokenA.mint(address(bob), sellSize);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), sellSize);
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdOne) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenA),
                sellPriceOne,
                sellSize / 2,
                0
            );
            stopMeasuringGas();
            startMeasuringGas('openERC20ToERC20Order');
            (, orderIdTwo) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenA),
                sellPriceTwo,
                sellSize / 2,
                1
            );
            stopMeasuringGas();
            vm.stopPrank();
        }
        {
            uint256 amountIn = publicLibrary.getERC20ToERC20AmountIn(address(tokenB), address(tokenA), sellSize);
            tokenB.mint(address(alice), amountIn);
            vm.startPrank(alice);
            tokenB.approve(address(publicLibrary), amountIn - 1);
            vm.expectRevert(abi.encodeWithSignature('AmountInTooHigh(uint256)', 750000000000000000));
            publicLibrary.swapERC20forExactERC20(
                sellSize,
                amountIn - 1,
                address(tokenB),
                address(tokenA),
                alice,
                block.timestamp
            );
        }
    }

    function _addressToUint(address _a) internal pure returns (uint256 v) {
        assembly {
            v := _a
        }
    }

    function testGetExactOutMultiPathABC() public {
        uint256 sellPriceAB = (10**36) / 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellPriceBC = (10**36) * 2100;
        uint256 sellSizeAB = 1 ether;
        uint256 sellSizeBC = 2100 ether;
        uint256 orderIdAB;
        uint256 orderIdBC;
        uint256 buySize = 2000 ether;
        {
            tokenB.mint(address(bob), sellSizeAB);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSizeAB);
            (, orderIdAB) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceAB,
                sellSizeAB,
                0
            );
            vm.stopPrank();
        }
        {
            tokenC.mint(address(bob), sellSizeBC);
            vm.startPrank(bob);
            tokenC.approve(address(publicLibrary), sellSizeBC);
            (, orderIdBC) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenC),
                sellPriceBC,
                sellSizeBC,
                0
            );
            vm.stopPrank();
        }
        uint256[] memory path = new uint256[](6);
        path[0] = 0;
        path[1] = _addressToUint(address(tokenA));
        path[2] = 0;
        path[3] = _addressToUint(address(tokenB));
        path[4] = 0;
        path[5] = _addressToUint(address(tokenC));
        {
            uint256[] memory amountsOut = publicLibrary.getAmountsOut(path, buySize);
            assert(amountsOut.length == 3);
            assert(amountsOut[0] == buySize);
            assert(amountsOut[1] == sellSizeAB);
            assert(amountsOut[2] == sellSizeBC);
        }
    }

    function testSwapExactInMultiPathABC() public {
        uint256 sellPriceAB = (10**36) / 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellPriceBC = (10**36) * 2100;
        uint256 sellSizeAB = 1 ether;
        uint256 sellSizeBC = 2100 ether;
        uint256 orderIdAB;
        uint256 orderIdBC;
        uint256 buySize = 2000 ether;
        {
            tokenB.mint(address(bob), sellSizeAB);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSizeAB);
            (, orderIdAB) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceAB,
                sellSizeAB,
                0
            );
            vm.stopPrank();
        }
        {
            tokenC.mint(address(bob), sellSizeBC);
            vm.startPrank(bob);
            tokenC.approve(address(publicLibrary), sellSizeBC);
            (, orderIdBC) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenC),
                sellPriceBC,
                sellSizeBC,
                0
            );
            vm.stopPrank();
        }
        uint256[] memory path = new uint256[](6);
        path[0] = 0;
        path[1] = _addressToUint(address(tokenA));
        path[2] = 0;
        path[3] = _addressToUint(address(tokenB));
        path[4] = 0;
        path[5] = _addressToUint(address(tokenC));
        {
            uint256[] memory amountsOut = publicLibrary.getAmountsOut(path, buySize);
            assert(amountsOut.length == 3);
            assert(amountsOut[0] == buySize);
            tokenA.mint(address(bob), amountsOut[0]);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), amountsOut[0]);
            assert(tokenC.balanceOf(bob) == 0);
            publicLibrary.swapExactInPath(amountsOut[0], amountsOut[2], path, bob, block.timestamp);
            assert(tokenC.balanceOf(bob) == sellSizeBC);
            vm.stopPrank();
        }
    }

    function testSwapExactInMultiPathFailABC() public {
        uint256 sellPriceAB = (10**36) / 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellPriceBC = (10**36) * 2100;
        uint256 sellSizeAB = 1 ether;
        uint256 sellSizeBC = 2100 ether;
        uint256 orderIdAB;
        uint256 orderIdBC;
        uint256 buySize = 2000 ether;
        {
            tokenB.mint(address(bob), sellSizeAB);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSizeAB);
            (, orderIdAB) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceAB,
                sellSizeAB,
                0
            );
            vm.stopPrank();
        }
        {
            tokenC.mint(address(bob), sellSizeBC);
            vm.startPrank(bob);
            tokenC.approve(address(publicLibrary), sellSizeBC);
            (, orderIdBC) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenC),
                sellPriceBC,
                sellSizeBC,
                0
            );
            vm.stopPrank();
        }
        uint256[] memory path = new uint256[](6);
        path[0] = 0;
        path[1] = _addressToUint(address(tokenA));
        path[2] = 0;
        path[3] = _addressToUint(address(tokenB));
        path[4] = 0;
        path[5] = _addressToUint(address(tokenC));
        {
            uint256[] memory amountsOut = publicLibrary.getAmountsOut(path, buySize);
            assert(amountsOut.length == 3);
            assert(amountsOut[0] == buySize);
            tokenA.mint(address(bob), amountsOut[0]);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), amountsOut[0]);
            vm.expectRevert(abi.encodeWithSignature('AmountOutTooLow(uint256)', 2100000000000000000000));
            publicLibrary.swapExactInPath(amountsOut[0], amountsOut[2] + 1, path, bob, block.timestamp);
            vm.stopPrank();
        }
    }

    function testGetExactInMultiPathABC() public {
        uint256 sellPriceAB = (10**36) / 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellPriceBC = (10**36) * 2100;
        uint256 sellSizeAB = 1 ether;
        uint256 sellSizeBC = 2100 ether;
        uint256 orderIdAB;
        uint256 orderIdBC;
        uint256 buySize = 2000 ether;
        {
            tokenB.mint(address(bob), sellSizeAB);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSizeAB);
            (, orderIdAB) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceAB,
                sellSizeAB,
                0
            );
            vm.stopPrank();
        }
        {
            tokenC.mint(address(bob), sellSizeBC);
            vm.startPrank(bob);
            tokenC.approve(address(publicLibrary), sellSizeBC);
            (, orderIdBC) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenC),
                sellPriceBC,
                sellSizeBC,
                0
            );
            vm.stopPrank();
        }
        uint256[] memory path = new uint256[](6);
        path[0] = 0;
        path[1] = _addressToUint(address(tokenA));
        path[2] = 0;
        path[3] = _addressToUint(address(tokenB));
        path[4] = 0;
        path[5] = _addressToUint(address(tokenC));
        {
            uint256[] memory amountsOut = publicLibrary.getAmountsIn(path, sellSizeBC);
            assert(amountsOut.length == 3);
            assert(amountsOut[0] == buySize);
            assert(amountsOut[1] == sellSizeAB);
            assert(amountsOut[2] == sellSizeBC);
        }
    }

    function testSwapExactOutMultiPathABC() public {
        uint256 sellPriceAB = (10**36) / 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellPriceBC = (10**36) * 2100;
        uint256 sellSizeAB = 1 ether;
        uint256 sellSizeBC = 2100 ether;
        uint256 orderIdAB;
        uint256 orderIdBC;
        uint256 buySize = 2000 ether;
        {
            tokenB.mint(address(bob), sellSizeAB);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSizeAB);
            (, orderIdAB) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceAB,
                sellSizeAB,
                0
            );
            vm.stopPrank();
        }
        {
            tokenC.mint(address(bob), sellSizeBC);
            vm.startPrank(bob);
            tokenC.approve(address(publicLibrary), sellSizeBC);
            (, orderIdBC) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenC),
                sellPriceBC,
                sellSizeBC,
                0
            );
            vm.stopPrank();
        }
        uint256[] memory path = new uint256[](6);
        path[0] = 0;
        path[1] = _addressToUint(address(tokenA));
        path[2] = 0;
        path[3] = _addressToUint(address(tokenB));
        path[4] = 0;
        path[5] = _addressToUint(address(tokenC));
        {
            uint256[] memory amountsOut = publicLibrary.getAmountsIn(path, sellSizeBC);
            assert(amountsOut.length == 3);
            assert(amountsOut[0] == buySize);
            tokenA.mint(address(bob), amountsOut[0]);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), amountsOut[0]);
            assert(tokenC.balanceOf(bob) == 0);
            publicLibrary.swapExactOutPath(amountsOut[2], amountsOut[0], path, bob, block.timestamp);
            assert(tokenC.balanceOf(bob) == sellSizeBC);
            vm.stopPrank();
        }
    }

    function testSwapExactOutMultiPathFailABC() public {
        uint256 sellPriceAB = (10**36) / 2000; // Read as => buy 1 ETH for 2000 USDC
        uint256 sellPriceBC = (10**36) * 2100;
        uint256 sellSizeAB = 1 ether;
        uint256 sellSizeBC = 2100 ether;
        uint256 orderIdAB;
        uint256 orderIdBC;
        uint256 buySize = 2000 ether;
        {
            tokenB.mint(address(bob), sellSizeAB);
            vm.startPrank(bob);
            tokenB.approve(address(publicLibrary), sellSizeAB);
            (, orderIdAB) = publicLibrary.openERC20ToERC20Order(
                address(tokenA),
                address(tokenB),
                sellPriceAB,
                sellSizeAB,
                0
            );
            vm.stopPrank();
        }
        {
            tokenC.mint(address(bob), sellSizeBC);
            vm.startPrank(bob);
            tokenC.approve(address(publicLibrary), sellSizeBC);
            (, orderIdBC) = publicLibrary.openERC20ToERC20Order(
                address(tokenB),
                address(tokenC),
                sellPriceBC,
                sellSizeBC,
                0
            );
            vm.stopPrank();
        }
        uint256[] memory path = new uint256[](6);
        path[0] = 0;
        path[1] = _addressToUint(address(tokenA));
        path[2] = 0;
        path[3] = _addressToUint(address(tokenB));
        path[4] = 0;
        path[5] = _addressToUint(address(tokenC));
        {
            uint256[] memory amountsOut = publicLibrary.getAmountsIn(path, sellSizeBC);
            assert(amountsOut.length == 3);
            assert(amountsOut[0] == buySize);
            tokenA.mint(address(bob), amountsOut[0]);
            vm.startPrank(bob);
            tokenA.approve(address(publicLibrary), amountsOut[0]);
            vm.expectRevert(abi.encodeWithSignature('AmountInTooHigh(uint256)', 2000000000000000000000));
            publicLibrary.swapExactOutPath(amountsOut[2], amountsOut[0] - 1, path, bob, block.timestamp);
            vm.stopPrank();
        }
    }
}
