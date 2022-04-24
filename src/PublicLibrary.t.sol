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
    uint8 internal decimalsA;
    uint256[3] internal tokenA_;
    ERC20Mock internal tokenB;
    uint8 internal decimalsB;
    uint256[3] internal tokenB_;
    ERC20Mock internal tokenC;
    uint8 internal decimalsC;
    uint256[3] internal tokenC_;
    Book internal book;
    bool internal tokenAisZero;

    address internal bob = address(1);
    address internal alice = address(2);

    function _addressToUint(address _a) internal pure returns (uint256 u) {
        assembly {
            u := _a
        }
    }

    function _uintToAddress(uint256 _v) internal pure returns (address a) {
        assembly {
            a := _v
        }
    }

    function setUp() public {
        printer = new Printer();
        tokenA = new ERC20Mock('US Dollar', 'USDC', 18);
        decimalsA = 18;
        tokenA_[0] = 0;
        tokenA_[1] = _addressToUint(address(tokenA));
        tokenA_[2] = 0;
        tokenB = new ERC20Mock('Wrapped Ether', 'WETH', 12);
        decimalsB = 12;
        tokenB_[0] = 0;
        tokenB_[1] = _addressToUint(address(tokenB));
        tokenB_[2] = 0;
        tokenC = new ERC20Mock('Dai Stablecoin', 'DAI', 6);
        decimalsC = 12;
        tokenC_[0] = 0;
        tokenC_[1] = _addressToUint(address(tokenC));
        tokenC_[2] = 0;
        book = Book(printer.createERC20Book(address(tokenA), address(tokenB)));
        printer.createERC20Book(address(tokenB), address(tokenC));
        publicLibrary = new PublicLibrary(address(printer));
        tokenAisZero = book.token0() == address(tokenA);
    }

    function _approve(
        uint256[3] memory token,
        address to,
        uint256 amount
    ) internal {
        if (token[0] == 0) {
            IERC20(_uintToAddress(token[1])).approve(to, amount);
        } else {
            IERC1155(_uintToAddress(token[1])).setApprovalForAll(to, true);
        }
    }

    function _mint(
        uint256[3] memory token,
        address to,
        uint256 amount
    ) internal {
        if (token[0] == 0) {
            ERC20Mock(_uintToAddress(token[1])).mint(to, amount);
        } else {
            ERC1155Mock(_uintToAddress(token[1])).mint(to, token[2], amount);
        }
    }

    function _getTokenOut(uint256[3] memory _tokenIn, uint256[3] memory _tokenOut) internal pure returns (uint8) {
        if (_tokenIn[0] == 0 && _tokenOut[0] == 0) {
            return _tokenOut[1] < _tokenIn[1] ? 0 : 1;
        } else if (_tokenIn[0] == 1 && _tokenOut[0] == 0) {
            return 1;
        } else if (_tokenIn[0] == 0 && _tokenOut[0] == 1) {
            return 0;
        } else {
            return (_tokenIn[1] == _tokenOut[1] ? _tokenOut[2] < _tokenIn[2] : _tokenOut[1] < _tokenIn[1]) ? 0 : 1;
        }
    }

    function _balanceOf(uint256[3] memory _token, address _owner) internal view returns (uint256) {
        if (_token[0] == 0) {
            return IERC20(_uintToAddress(_token[1])).balanceOf(_owner);
        } else {
            return IERC1155(_uintToAddress(_token[1])).balanceOf(_owner, _token[2]);
        }
    }

    function _getOrderToken(address _book, uint256 _orderId) internal pure returns (uint256[3] memory token) {
        token[0] = 1;
        token[1] = _addressToUint(_book);
        token[2] = _orderId;
    }

    function _getAmountIn(
        uint256 _amountOut,
        uint256 _price,
        uint8 _decimals
    ) internal pure returns (uint256) {
        return ((_amountOut * (10**(_decimals))) / _price);
    }

    function _getAmountOut(
        uint256 _amountIn,
        uint256 _price,
        uint8 _decimals
    ) internal pure returns (uint256) {
        return ((_amountIn * _price) / 10**(_decimals));
    }

    function testOpenAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            uint256[3] memory orderToken = _getOrderToken(_book, orderId);
            assertEq(_balanceOf(orderToken, bob), _getAmountIn(amount, price, decimalsA + decimalsB));
            vm.stopPrank();
        }
    }

    function testOpenABInvalidPrice() public {
        uint256 price = (10**(decimalsA + decimalsB) * 2000) + 1;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            vm.expectRevert(abi.encodeWithSignature('InvalidPrice()'));
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
    }

    function testOpenABNullAmount() public {
        uint256 price = (10**(decimalsA + decimalsB) * 2000);
        uint256 amount = 0;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            vm.expectRevert(abi.encodeWithSignature('MultiTokenOrderCreation()'));
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
    }

    function testOpenBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            uint256[3] memory orderToken = _getOrderToken(_book, orderId);
            assertEq(_balanceOf(orderToken, bob), _getAmountIn(amount, price, decimalsA + decimalsB));
            vm.stopPrank();
        }
    }

    function testOpenBAInvalidPrice() public {
        uint256 price = (10**(decimalsA + decimalsB) / 2000) + 1;
        uint256 amount = 2000 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            vm.expectRevert(abi.encodeWithSignature('InvalidPrice()'));
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }
    }

    function testOpenBANullAmount() public {
        uint256 price = (10**(decimalsA + decimalsB) / 2000);
        uint256 amount = 0;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            vm.expectRevert(abi.encodeWithSignature('MultiTokenOrderCreation()'));
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }
    }

    function testGetAmountOutAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        assertEq(publicLibrary.getAmountOut(1 ether, tokenA_, tokenB_), amount);
    }

    function testGetAmountInAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        assertEq(publicLibrary.getAmountIn(amount, tokenA_, tokenB_), 1 ether);
    }

    function testGetAmountOutBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        assertEq(publicLibrary.getAmountOut(2000 ether, tokenA_, tokenB_), amount);
    }

    function testGetAmountInBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        assertEq(publicLibrary.getAmountIn(amount, tokenA_, tokenB_), 2000 ether);
    }

    function testOpenTwoAscAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            uint256[3] memory orderToken = _getOrderToken(_book, orderId);
            assertEq(_balanceOf(orderToken, bob), _getAmountIn(amount, price, decimalsA + decimalsB));
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            uint256[3] memory orderToken = _getOrderToken(_book, orderId);
            assertEq(_balanceOf(orderToken, bob), _getAmountIn(amount, price, decimalsA + decimalsB));
            vm.stopPrank();
        }
    }

    function testOpenTwoDescAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            uint256[3] memory orderToken = _getOrderToken(_book, orderId);
            assertEq(_balanceOf(orderToken, bob), _getAmountIn(amount, price, decimalsA + decimalsB));
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) * 2200;
        amount = 2200 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 1);
            uint256[3] memory orderToken = _getOrderToken(_book, orderId);
            assertEq(_balanceOf(orderToken, bob), _getAmountIn(amount, price, decimalsA + decimalsB));
            vm.stopPrank();
        }
    }

    function testOpenTwoAscBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            uint256[3] memory orderToken = _getOrderToken(_book, orderId);
            assertEq(_balanceOf(orderToken, bob), _getAmountIn(amount, price, decimalsA + decimalsB));
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) / 4000;
        amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            uint256[3] memory orderToken = _getOrderToken(_book, orderId);
            assertEq(_balanceOf(orderToken, bob), _getAmountIn(amount, price, decimalsA + decimalsB));
            vm.stopPrank();
        }
    }

    function testOpenTwoDescBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000; // How many WETH per USDC
        uint256 amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            uint256[3] memory orderToken = _getOrderToken(_book, orderId);
            assertEq(_balanceOf(orderToken, bob), _getAmountIn(amount, price, decimalsA + decimalsB));
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) / 500;
        amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 1);
            uint256[3] memory orderToken = _getOrderToken(_book, orderId);
            assertEq(_balanceOf(orderToken, bob), _getAmountIn(amount, price, decimalsA + decimalsB));
            vm.stopPrank();
        }
    }

    function testGetAmountOutTwoOrdersAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }

        assertEq(publicLibrary.getAmountOut(2 ether, tokenA_, tokenB_), 3800 ether);
    }

    function testGetAmountInTwoOrdersAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }

        assertEq(publicLibrary.getAmountIn(3800 ether, tokenA_, tokenB_), 2 ether);
    }

    function testGetAmountOutTwoOrdersBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) / 4000;
        amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }

        assertEq(publicLibrary.getAmountOut(6000 ether, tokenB_, tokenA_), 2 ether);
    }

    function testGetAmountInTwoOrdersBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) / 4000;
        amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }

        assertEq(publicLibrary.getAmountIn(2 ether, tokenB_, tokenA_), 6000 ether);
    }

    function testSwapETFTUniqueOrderAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(amount, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            publicLibrary.swapExactTokenForToken(amountIn, 2000 ether, tokenA_, tokenB_, alice, block.timestamp);
            assertEq(_balanceOf(tokenB_, alice), 2000 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), amountIn);
    }

    function testSwapETFTHalfUniqueOrderAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(amount / 2, tokenA_, tokenB_);
        uint256 totalAmountIn = publicLibrary.getAmountIn(amount, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        assertEq(_balanceOf(order, bob), totalAmountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            publicLibrary.swapExactTokenForToken(amountIn, 1000 ether, tokenA_, tokenB_, alice, block.timestamp);
            assertEq(_balanceOf(tokenB_, alice), 1000 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), totalAmountIn / 2);
        ++order[2];
        assertEq(_balanceOf(order, bob), totalAmountIn / 2);
    }

    function testSwapETFTTwoOrderAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }

        uint256 amountIn = publicLibrary.getAmountIn(3800 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            publicLibrary.swapExactTokenForToken(amountIn, 3800 ether, tokenA_, tokenB_, alice, block.timestamp);
            assertEq(_balanceOf(tokenB_, alice), 3800 ether);
            vm.stopPrank();
        }
    }

    function testSwapETFTTwoOrderOneFilledAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }

        uint256 amountIn = publicLibrary.getAmountIn(2000 ether, tokenA_, tokenB_);
        uint256 firstOrderAmountData = publicLibrary.getAmountIn(2000 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        assertEq(_balanceOf(order, bob), firstOrderAmountData);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            publicLibrary.swapExactTokenForToken(amountIn, 2000 ether, tokenA_, tokenB_, alice, block.timestamp);
            assertEq(_balanceOf(tokenB_, alice), 2000 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), firstOrderAmountData);
    }

    function testSwapETFTDeadlineCrossedAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(amount, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            vm.expectRevert(abi.encodeWithSignature('DeadlineCrossed()'));
            vm.warp(100);
            publicLibrary.swapExactTokenForToken(amountIn, 2000 ether, tokenA_, tokenB_, alice, block.timestamp - 1);
            vm.stopPrank();
        }
    }

    function testSwapETFTAmountOutTooLowAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(amount, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            vm.expectRevert(abi.encodeWithSignature('AmountOutTooLow(uint256)', 2000000000000000000000));
            publicLibrary.swapExactTokenForToken(amountIn, 2000 ether + 1, tokenA_, tokenB_, alice, block.timestamp);
            vm.stopPrank();
        }
    }

    // duplicate for BA
    function testSwapETFTUniqueOrderBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(amount, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenA_, alice), 0);
            publicLibrary.swapExactTokenForToken(amountIn, 1 ether, tokenB_, tokenA_, alice, block.timestamp);
            assertEq(_balanceOf(tokenA_, alice), 1 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), amountIn);
    }

    function testSwapETFTHalfUniqueOrderBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(amount / 2, tokenB_, tokenA_);
        uint256 totalAmountIn = publicLibrary.getAmountIn(amount, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        assertEq(_balanceOf(order, bob), totalAmountIn);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenA_, alice), 0);
            publicLibrary.swapExactTokenForToken(amountIn, 0.5 ether, tokenB_, tokenA_, alice, block.timestamp);
            assertEq(_balanceOf(tokenA_, alice), 0.5 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), totalAmountIn / 2);
        ++order[2];
        assertEq(_balanceOf(order, bob), totalAmountIn / 2);
    }

    function testSwapETFTTwoOrderBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) / 4000;
        amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }

        uint256 amountIn = publicLibrary.getAmountIn(2 ether, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenA_, alice), 0);
            publicLibrary.swapExactTokenForToken(amountIn, 2 ether, tokenB_, tokenA_, alice, block.timestamp);
            assertEq(_balanceOf(tokenA_, alice), 2 ether);
            vm.stopPrank();
        }
    }

    function testSwapETFTTwoOrderOneFilledBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        price = 10**(decimalsA + decimalsB) / 4000;
        amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }

        uint256 amountIn = publicLibrary.getAmountIn(1 ether, tokenB_, tokenA_);
        uint256 firstOrderAmountData = publicLibrary.getAmountIn(1 ether, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        assertEq(_balanceOf(order, bob), firstOrderAmountData);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenA_, alice), 0);
            publicLibrary.swapExactTokenForToken(amountIn, 1 ether, tokenB_, tokenA_, alice, block.timestamp);
            assertEq(_balanceOf(tokenA_, alice), 1 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), firstOrderAmountData);
    }

    function testSwapETFTDeadlineCrossedBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(amount, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amount);
            assertEq(_balanceOf(tokenA_, alice), 0);
            vm.warp(100);
            vm.expectRevert(abi.encodeWithSignature('DeadlineCrossed()'));
            publicLibrary.swapExactTokenForToken(amountIn, 1 ether, tokenB_, tokenA_, alice, block.timestamp - 1);
            vm.stopPrank();
        }
    }

    function testSwapETFTAmountOutTooLowBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(amount, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amount);
            assertEq(_balanceOf(tokenA_, alice), 0);
            vm.expectRevert(abi.encodeWithSignature('AmountOutTooLow(uint256)', 1000000000000000000));
            publicLibrary.swapExactTokenForToken(amountIn, 1 ether + 1, tokenB_, tokenA_, alice, block.timestamp);
            vm.stopPrank();
        }
    }

    function testSwapTFETUniqueOrderAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountOut = publicLibrary.getAmountOut(1 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, 1 ether);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), 1 ether);
            assertEq(_balanceOf(tokenB_, alice), 0);
            publicLibrary.swapTokenForExactToken(amountOut, 1 ether, tokenA_, tokenB_, alice, block.timestamp);
            assertEq(_balanceOf(tokenB_, alice), 2000 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), 1 ether);
    }

    function testSwapTFETHalfUniqueOrderAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountOut = publicLibrary.getAmountOut(0.5 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountOut);
        assertEq(_balanceOf(order, bob), 1 ether);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), 0.5 ether);
            assertEq(_balanceOf(tokenB_, alice), 0);
            publicLibrary.swapTokenForExactToken(amountOut, 0.5 ether, tokenA_, tokenB_, alice, block.timestamp);
            assertEq(_balanceOf(tokenB_, alice), 1000 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0.5 ether);
        ++order[2];
        assertEq(_balanceOf(order, bob), 0.5 ether);
    }

    function testSwapTFETTwoOrderAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        uint256 amountIn = 2 ether;
        uint256 amountOut = publicLibrary.getAmountOut(amountIn, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            publicLibrary.swapTokenForExactToken(amountOut, amountIn, tokenA_, tokenB_, alice, block.timestamp);
            assertEq(_balanceOf(tokenB_, alice), 3800 ether);
            vm.stopPrank();
        }
    }

    function testSwapTFETTwoOrderOneFilledAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        uint256 amountIn = 2 ether;
        uint256 amountOut = publicLibrary.getAmountOut(amountIn / 2, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        assertEq(_balanceOf(order, bob), amountIn / 2);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            publicLibrary.swapTokenForExactToken(amountOut, amountIn / 2, tokenA_, tokenB_, alice, block.timestamp);
            assertEq(_balanceOf(tokenB_, alice), 2000 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), amountIn / 2);
    }

    function testSwapTFETDeadlineCrossedAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = 1 ether;
        uint256 amountOut = publicLibrary.getAmountOut(amountIn, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            vm.expectRevert(abi.encodeWithSignature('DeadlineCrossed()'));
            vm.warp(100);
            publicLibrary.swapTokenForExactToken(amountOut, amountIn, tokenA_, tokenB_, alice, block.timestamp - 1);
            vm.stopPrank();
        }
    }

    function testSwapTFETAmountOutTooLowAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = 1 ether;
        uint256 amountOut = publicLibrary.getAmountOut(amountIn, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            vm.expectRevert(abi.encodeWithSignature('AmountInTooHigh(uint256)', 1000000000000000000));
            publicLibrary.swapTokenForExactToken(amountOut, amountIn - 1, tokenA_, tokenB_, alice, block.timestamp);
            vm.stopPrank();
        }
    }

    function testSwapTFETUniqueOrderBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = 2000 ether;
        uint256 amountOut = publicLibrary.getAmountOut(amountIn, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenA_, alice), 0);
            publicLibrary.swapTokenForExactToken(amountOut, amountIn, tokenB_, tokenA_, alice, block.timestamp);
            assertEq(_balanceOf(tokenA_, alice), amountOut);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), amountIn);
    }

    function testSwapTFETHalfUniqueOrderBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = 1000 ether;
        uint256 amountOut = publicLibrary.getAmountOut(amountIn, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        assertEq(_balanceOf(order, bob), 2000 ether);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenA_, alice), 0);
            publicLibrary.swapTokenForExactToken(amountOut, amountIn, tokenB_, tokenA_, alice, block.timestamp);
            assertEq(_balanceOf(tokenA_, alice), 0.5 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 1000 ether);
        ++order[2];
        assertEq(_balanceOf(order, bob), 1000 ether);
    }

    function testSwapTFETTwoOrderBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }
        price = 10**(decimalsA + decimalsB) / 4000;
        amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }
        uint256 amountIn = 6000 ether;
        uint256 amountOut = publicLibrary.getAmountOut(6000 ether, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenA_, alice), 0);
            publicLibrary.swapTokenForExactToken(amountOut, amountIn, tokenB_, tokenA_, alice, block.timestamp);
            assertEq(_balanceOf(tokenA_, alice), 2 ether);
            vm.stopPrank();
        }
    }

    function testSwapTFETTwoOrderOneFilledBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        price = 10**(decimalsA + decimalsB) / 4000;
        amount = 1 ether;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
        }
        uint256 amountIn = 2000 ether;
        uint256 amountOut = publicLibrary.getAmountOut(amountIn, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        assertEq(_balanceOf(order, bob), amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenA_, alice), 0);
            publicLibrary.swapTokenForExactToken(amountOut, amountIn, tokenB_, tokenA_, alice, block.timestamp);
            assertEq(_balanceOf(tokenA_, alice), 1 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), amountIn);
    }

    function testSwapTFETDeadlineCrossedBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = 2000 ether;
        uint256 amountOut = publicLibrary.getAmountOut(amountIn, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenA_, alice), 0);
            vm.warp(100);
            vm.expectRevert(abi.encodeWithSignature('DeadlineCrossed()'));
            publicLibrary.swapTokenForExactToken(amountOut, amountIn, tokenB_, tokenA_, alice, block.timestamp - 1);
            vm.stopPrank();
        }
    }

    function testSwapTFETAmountOutTooLowBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = 2000 ether;
        uint256 amountOut = publicLibrary.getAmountOut(amountIn, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amount);
            assertEq(_balanceOf(tokenA_, alice), 0);
            vm.expectRevert(abi.encodeWithSignature('AmountInTooHigh(uint256)', 2000000000000000000000));
            publicLibrary.swapTokenForExactToken(amountOut, amountIn - 1, tokenB_, tokenA_, alice, block.timestamp);
            vm.stopPrank();
        }
    }

    function testSwapTFETInvalidMultipleAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        uint256 amountOut = publicLibrary.getAmountOut(1 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, 2000 ether);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amount);
            vm.expectRevert(
                abi.encodeWithSignature(
                    'AmountOutNotMultipleOfPrice(uint256,uint256)',
                    1999999999999999999999,
                    2000000000000000000000000000000000
                )
            );
            publicLibrary.swapTokenForExactToken(amountOut - 1, 2000 ether, tokenA_, tokenB_, alice, block.timestamp);
            vm.stopPrank();
        }
    }

    // swap max AB
    function testSwapMaxUniqueOrderAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(2000 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            (uint256 finalAmountIn, uint256 finalAmountOut) = publicLibrary.swapMaxAbovePrice(
                amountIn,
                price,
                tokenA_,
                tokenB_,
                alice,
                block.timestamp
            );
            assertEq(finalAmountIn, amountIn);
            assertEq(finalAmountOut, 2000 ether);
            assertEq(_balanceOf(tokenB_, alice), 2000 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), amountIn);
    }

    function testSwapMaxUniqueOrderNotMultipleAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(2000 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn + 1);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn + 1);
            assertEq(_balanceOf(tokenB_, alice), 0);
            (uint256 finalAmountIn, uint256 finalAmountOut) = publicLibrary.swapMaxAbovePrice(
                amountIn + 1,
                price,
                tokenA_,
                tokenB_,
                alice,
                block.timestamp
            );
            assertEq(finalAmountIn, amountIn);
            assertEq(finalAmountOut, 2000 ether);
            assertEq(_balanceOf(tokenB_, alice), 2000 ether);
            assertEq(_balanceOf(tokenA_, alice), 1);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), amountIn);
    }

    function testSwapMaxUniqueOrderHalfFillAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(1000 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            (uint256 finalAmountIn, uint256 finalAmountOut) = publicLibrary.swapMaxAbovePrice(
                amountIn,
                price,
                tokenA_,
                tokenB_,
                alice,
                block.timestamp
            );
            assertEq(finalAmountIn, amountIn);
            assertEq(finalAmountOut, 1000 ether);
            assertEq(_balanceOf(tokenB_, alice), 1000 ether);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), amountIn);
        ++order[2];
        assertEq(_balanceOf(order, bob), amountIn);
    }

    function testSwapMaxTwoOrdersAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        uint256 amountIn = publicLibrary.getAmountIn(3800 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            (uint256 finalAmountIn, uint256 finalAmountOut) = publicLibrary.swapMaxAbovePrice(
                amountIn,
                price,
                tokenA_,
                tokenB_,
                alice,
                block.timestamp
            );
            assertEq(finalAmountIn, amountIn);
            assertEq(finalAmountOut, 3800 ether);
            assertEq(_balanceOf(tokenB_, alice), 3800 ether);
            assertEq(_balanceOf(tokenA_, alice), 0);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), 1 ether);
    }

    function testSwapMaxTwoOrdersOutpricingOneAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        uint256 amountIn = publicLibrary.getAmountIn(2000 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn);
        {
            price = 10**(decimalsA + decimalsB) * 2000;
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn);
            assertEq(_balanceOf(tokenB_, alice), 0);
            (uint256 finalAmountIn, uint256 finalAmountOut) = publicLibrary.swapMaxAbovePrice(
                amountIn,
                price,
                tokenA_,
                tokenB_,
                alice,
                block.timestamp
            );
            assertEq(finalAmountIn, amountIn);
            assertEq(finalAmountOut, 2000 ether);
            assertEq(_balanceOf(tokenB_, alice), 2000 ether);
            assertEq(_balanceOf(tokenA_, alice), 0);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), 1 ether);
    }

    function testSwapMaxTwoOrdersNotMultipleAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        uint256 amountIn = publicLibrary.getAmountIn(3800 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn + 1);
        {
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn + 1);
            assertEq(_balanceOf(tokenB_, alice), 0);
            (uint256 finalAmountIn, uint256 finalAmountOut) = publicLibrary.swapMaxAbovePrice(
                amountIn + 1,
                price,
                tokenA_,
                tokenB_,
                alice,
                block.timestamp
            );
            assertEq(finalAmountIn, amountIn);
            assertEq(finalAmountOut, 3800 ether);
            assertEq(_balanceOf(tokenB_, alice), 3800 ether);
            assertEq(_balanceOf(tokenA_, alice), 1);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), 1 ether);
    }

    function testSwapMaxTwoOrdersOutpricingOneNotMultipleAB() public {
        uint256 price = 10**(decimalsA + decimalsB) * 2000;
        uint256 amount = 2000 ether;
        uint256[3] memory order;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        price = 10**(decimalsA + decimalsB) * 1800;
        amount = 1800 ether;
        _mint(tokenB_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenB_, address(publicLibrary), amount);
            publicLibrary.open(tokenA_, tokenB_, price, amount, 0);
            vm.stopPrank();
        }
        uint256 amountIn = publicLibrary.getAmountIn(2000 ether, tokenA_, tokenB_);
        _mint(tokenA_, alice, amountIn + 1);
        {
            price = 10**(decimalsA + decimalsB) * 2000;
            vm.startPrank(alice);
            _approve(tokenA_, address(publicLibrary), amountIn + 1);
            assertEq(_balanceOf(tokenB_, alice), 0);
            (uint256 finalAmountIn, uint256 finalAmountOut) = publicLibrary.swapMaxAbovePrice(
                amountIn + 1,
                price,
                tokenA_,
                tokenB_,
                alice,
                block.timestamp
            );
            assertEq(finalAmountIn, amountIn);
            assertEq(finalAmountOut, 2000 ether);
            assertEq(_balanceOf(tokenB_, alice), 2000 ether);
            assertEq(_balanceOf(tokenA_, alice), 1);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), 0);
        ++order[2];
        assertEq(_balanceOf(order, bob), 1 ether);
    }

    // swap max BA
    function testSwapMaxUniqueOrderNotMultipleHalfFillBA() public {
        uint256 price = 10**(decimalsA + decimalsB) / 2000;
        uint256 amount = 1 ether;
        uint256[3] memory order;
        _mint(tokenA_, bob, amount);
        {
            vm.startPrank(bob);
            _approve(tokenA_, address(publicLibrary), amount);
            (address _book, uint256 orderId) = publicLibrary.open(tokenB_, tokenA_, price, amount, 0);
            vm.stopPrank();
            order = _getOrderToken(_book, orderId);
        }
        uint256 amountIn = publicLibrary.getAmountIn(0.5 ether, tokenB_, tokenA_);
        _mint(tokenB_, alice, amountIn + 1);
        {
            vm.startPrank(alice);
            _approve(tokenB_, address(publicLibrary), amountIn + 1);
            assertEq(_balanceOf(tokenA_, alice), 0);
            (uint256 finalAmountIn, uint256 finalAmountOut) = publicLibrary.swapMaxAbovePrice(
                amountIn + 1,
                price,
                tokenB_,
                tokenA_,
                alice,
                block.timestamp
            );
            assertEq(finalAmountIn, amountIn);
            assertEq(finalAmountOut, 0.5 ether);
            assertEq(_balanceOf(tokenA_, alice), 0.5 ether);
            assertEq(_balanceOf(tokenB_, alice), 1);
            vm.stopPrank();
        }
        assertEq(_balanceOf(order, bob), amountIn);
        ++order[2];
        assertEq(_balanceOf(order, bob), amountIn);
    }

    // swap exact In Path AB
    // swap exact In Path BA
    // swap exact Out Path AB
    // swap exact Out Path BA
}
