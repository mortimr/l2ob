// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.10;

import "ds-test/test.sol";

contract ContractTest is DSTest {
    function setUp() public {}

    function testExample() public {
        assertTrue(true);
    }
}

contract ContractFuzz is DSTest {
    function setUp() public {}

    function testExample(address) public {
        assertTrue(true);
    }
}
