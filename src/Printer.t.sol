// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.6;

import 'solmate/test/utils/DSTestPlus.sol';
import 'solmate/tokens/ERC1155.sol';
import 'solmate/tokens/ERC20.sol';
import 'forge-std/Vm.sol';

import './test/console.sol';

import './Printer.sol';

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

contract PrinterERC20ERC20Test is DSTestPlus {
    Vm public constant vm = Vm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    Printer internal printer;
    ERC20Mock internal tokenA;
    ERC20Mock internal tokenB;

    address internal bob = address(1);
    address internal alice = address(2);

    function setUp() public {
        printer = new Printer();
        tokenA = new ERC20Mock('US Dollar', 'USDC', 18);
        tokenB = new ERC20Mock('Wrapped Ether', 'WETH', 18);
    }

    function testCreateBook() public {
        startMeasuringGas('create ERC20+ERC20 book');
        address book = printer.createERC20Book(address(tokenA), address(tokenB));
        stopMeasuringGas();
        if (address(tokenA) < address(tokenB)) {
            assert(IBook(book).token0() == address(tokenA));
            assert(IBook(book).token1() == address(tokenB));
            assert(IBook(book).decimals0() == 18);
            assert(IBook(book).decimals1() == 18);
            assert(IBook(book).id0() == 0);
            assert(IBook(book).id1() == 0);
        } else {
            assert(IBook(book).token1() == address(tokenA));
            assert(IBook(book).token0() == address(tokenB));
            assert(IBook(book).decimals0() == 18);
            assert(IBook(book).decimals1() == 18);
            assert(IBook(book).id0() == 0);
            assert(IBook(book).id1() == 0);
        }
        assert(printer.bookForERC20(address(tokenA), address(tokenB)) == book);
        assert(printer.bookForERC20(address(tokenB), address(tokenA)) == book);
    }

    function testCreateBookDuplicate() public {
        address book = printer.createERC20Book(address(tokenA), address(tokenB));
        assert(printer.bookForERC20(address(tokenA), address(tokenB)) == book);
        assert(printer.bookForERC20(address(tokenB), address(tokenA)) == book);
        vm.expectRevert(abi.encodeWithSignature('BookAlreadyExists()'));
        book = printer.createERC20Book(address(tokenA), address(tokenB));
    }

    function testSameAsset() public {
        vm.expectRevert(abi.encodeWithSignature('InvalidTokens()'));
        printer.createERC20Book(address(tokenA), address(tokenA));
    }
}

contract PrinterERC1155ERC1155Test is DSTestPlus {
    Vm public constant vm = Vm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    Printer internal printer;
    ERC1155Mock internal tokenA;
    ERC1155Mock internal tokenB;
    uint256 idA = 1;
    uint256 idB = 2;

    address internal bob = address(1);
    address internal alice = address(2);

    function setUp() public {
        printer = new Printer();
        tokenA = new ERC1155Mock();
        tokenB = new ERC1155Mock();
    }

    function testCreateBook() public {
        startMeasuringGas('create ERC1155+ERC1155 book');
        address book = printer.createERC1155Book(address(tokenA), idA, address(tokenB), idB);
        stopMeasuringGas();
        if (address(tokenA) < address(tokenB)) {
            assert(IBook(book).token0() == address(tokenA));
            assert(IBook(book).token1() == address(tokenB));
            assert(IBook(book).decimals0() == 0);
            assert(IBook(book).decimals1() == 0);
            assert(IBook(book).id0() == idA);
            assert(IBook(book).id1() == idB);
        } else {
            assert(IBook(book).token1() == address(tokenA));
            assert(IBook(book).token0() == address(tokenB));
            assert(IBook(book).decimals0() == 0);
            assert(IBook(book).decimals1() == 0);
            assert(IBook(book).id0() == idB);
            assert(IBook(book).id1() == idA);
        }
        assert(printer.bookForERC1155(address(tokenA), idA, address(tokenB), idB) == book);
        assert(printer.bookForERC1155(address(tokenB), idB, address(tokenA), idA) == book);
    }

    function testCreateBookDuplicate() public {
        address book = printer.createERC1155Book(address(tokenA), idA, address(tokenB), idB);
        assert(printer.bookForERC1155(address(tokenA), idA, address(tokenB), idB) == book);
        assert(printer.bookForERC1155(address(tokenB), idB, address(tokenA), idA) == book);
        vm.expectRevert(abi.encodeWithSignature('BookAlreadyExists()'));
        book = printer.createERC1155Book(address(tokenA), idA, address(tokenB), idB);
    }

    function testSameAsset() public {
        vm.expectRevert(abi.encodeWithSignature('InvalidTokens()'));
        printer.createERC1155Book(address(tokenA), idA, address(tokenA), idA);
    }
}

contract PrinterERC1155SingleTest is DSTestPlus {
    Vm public constant vm = Vm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    Printer internal printer;
    ERC1155Mock internal token;
    uint256 idA = 1;
    uint256 idB = 2;

    address internal bob = address(1);
    address internal alice = address(2);

    function setUp() public {
        printer = new Printer();
        token = new ERC1155Mock();
    }

    function testCreateBook() public {
        startMeasuringGas('create ERC1155+ERC1155 book');
        address book = printer.createERC1155Book(address(token), idA, address(token), idB);
        stopMeasuringGas();
        if (idA < idB) {
            assert(IBook(book).token0() == address(token));
            assert(IBook(book).token1() == address(token));
            assert(IBook(book).decimals0() == 0);
            assert(IBook(book).decimals1() == 0);
            assert(IBook(book).id0() == idA);
            assert(IBook(book).id1() == idB);
        } else {
            assert(IBook(book).token1() == address(token));
            assert(IBook(book).token0() == address(token));
            assert(IBook(book).decimals0() == 0);
            assert(IBook(book).decimals1() == 0);
            assert(IBook(book).id0() == idB);
            assert(IBook(book).id1() == idA);
        }
        assert(printer.bookForERC1155(address(token), idA, address(token), idB) == book);
        assert(printer.bookForERC1155(address(token), idB, address(token), idA) == book);
    }

    function testCreateBookDuplicate() public {
        address book = printer.createERC1155Book(address(token), idA, address(token), idB);
        assert(printer.bookForERC1155(address(token), idA, address(token), idB) == book);
        assert(printer.bookForERC1155(address(token), idB, address(token), idA) == book);
        vm.expectRevert(abi.encodeWithSignature('BookAlreadyExists()'));
        book = printer.createERC1155Book(address(token), idA, address(token), idB);
    }

    function testSameAsset() public {
        vm.expectRevert(abi.encodeWithSignature('InvalidTokens()'));
        printer.createERC1155Book(address(token), idA, address(token), idA);
    }
}

contract PrinterERC1155ERC20Test is DSTestPlus {
    Vm public constant vm = Vm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    Printer internal printer;
    ERC1155Mock internal tokenA;
    ERC20Mock internal tokenB;
    uint256 idA = 1;

    address internal bob = address(1);
    address internal alice = address(2);

    function setUp() public {
        printer = new Printer();
        tokenA = new ERC1155Mock();
        tokenB = new ERC20Mock('Wrapped Ether', 'WETH', 18);
    }

    function testCreateBook() public {
        startMeasuringGas('create ERC1155+ERC20 book');
        address book = printer.createHybridBook(address(tokenA), idA, address(tokenB));
        stopMeasuringGas();
        assert(IBook(book).token0() == address(tokenA));
        assert(IBook(book).token1() == address(tokenB));
        assert(IBook(book).decimals0() == 0);
        assert(IBook(book).decimals1() == 18);
        assert(IBook(book).id0() == idA);
        assert(IBook(book).id1() == 0);
        assert(printer.bookForHybrid(address(tokenA), idA, address(tokenB)) == book);
    }

    function testCreateBookDuplicate() public {
        address book = printer.createHybridBook(address(tokenA), idA, address(tokenB));
        assert(printer.bookForHybrid(address(tokenA), idA, address(tokenB)) == book);
        vm.expectRevert(abi.encodeWithSignature('BookAlreadyExists()'));
        book = printer.createHybridBook(address(tokenA), idA, address(tokenB));
    }

    function testSameAsset() public {
        vm.expectRevert(abi.encodeWithSignature('InvalidTokens()'));
        printer.createHybridBook(address(tokenA), idA, address(tokenA));
    }
}

contract PrinterERC20ERC1155Test is DSTestPlus {
    Vm public constant vm = Vm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    Printer internal printer;
    ERC20Mock internal tokenA;
    ERC1155Mock internal tokenB;
    uint256 idB = 1;

    address internal bob = address(1);
    address internal alice = address(2);

    function setUp() public {
        printer = new Printer();
        tokenA = new ERC20Mock('Wrapped Ether', 'WETH', 18);
        tokenB = new ERC1155Mock();
    }

    function testCreateBook() public {
        startMeasuringGas('create ERC20+ERC1155 book');
        address book = printer.createHybridBook(address(tokenB), idB, address(tokenA));
        stopMeasuringGas();
        assert(IBook(book).token0() == address(tokenB));
        assert(IBook(book).token1() == address(tokenA));
        assert(IBook(book).decimals0() == 0);
        assert(IBook(book).decimals1() == 18);
        assert(IBook(book).id0() == idB);
        assert(IBook(book).id1() == 0);
        assert(printer.bookForHybrid(address(tokenB), idB, address(tokenA)) == book);
    }

    function testCreateBookDuplicate() public {
        address book = printer.createHybridBook(address(tokenB), idB, address(tokenA));
        assert(printer.bookForHybrid(address(tokenB), idB, address(tokenA)) == book);
        vm.expectRevert(abi.encodeWithSignature('BookAlreadyExists()'));
        book = printer.createHybridBook(address(tokenB), idB, address(tokenA));
    }

    function testSameAsset() public {
        vm.expectRevert(abi.encodeWithSignature('InvalidTokens()'));
        printer.createHybridBook(address(tokenB), idB, address(tokenB));
    }
}
