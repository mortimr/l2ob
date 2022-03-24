//SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

interface IPairBookCaller {
    function pairBookCallback(
        uint256 amount0Out,
        uint256 amount0In,
        uint256 debt0,
        uint256 debt1,
        address caller,
        bytes memory data
    ) external;
}
