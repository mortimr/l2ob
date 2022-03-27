//SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

interface IBookCaller {
    function bookCallback(
        uint256 _amount0Out,
        uint256 _amount0In,
        uint256 _debt0,
        uint256 _debt1,
        address _caller,
        bytes memory _data
    ) external;
}
