// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/MiniswapFactory.sol";
import "../libraries/TransferHelper.sol";

import "../interfaces/IMiniswapRouter.sol";
import "../interfaces/IERC20.sol";

import "../libraries/MiniswapLibrary.sol";
import "../libraries/SafeMath.sol";

contract MiniswapRouter {
    using SafeMath for uint;

    address public factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal returns (uint amountA, uint amountB) {
        // 유동성을 추가할 때, 이전에 pair가 존재하지 않는 경우
        if (IMiniswapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // amountA, amountB토큰 입금 희망량을 기준으로 이상적인 상대 토큰 입금량 계산
            uint amountBOptimal = MiniswapLibrary.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            // 입금하고자 하는 양보다 입금에 필요한 양이 적을 때
            if (amountBOptomal <= amountBDesired) {
                // 최소 기준치보다는 입금량이 커야함
                require(amountBOptimal >= amoountBMin);
                (amountA, amountB) = (amountADesired, amountBOptimal);
                // 입금하고자 하는 양보다 입금에 필요한 양이 클 때는 반대로 계산하여 주어진 자산 내에서 동작하도록 한다.
            } else {
                uint amountAOptimal = MiniswapLibrary.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // 유동성을 추가하는 함수
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        address pair = MiniswapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IMiniswapPair(pair).mint(to);
    }

    // 유동성을 제거하는 함수
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to
    ) public returns (uint amountA, uint amountB) {
        address pair = MiniswapLibrary.pairFor(factory, tokenA, tokenB);
        IMiniswapPair(pair).transferFrom(msg.sender, pair, liquidity);
        (uint amount0, uint amount1) = IMiniswapPair(pair).burn(to);
        (address token0, ) = MiniswapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(amountA >= amountAMin && amountB >= amountBMin);
    }

    function _swap(
        uint[] memory amounts,
        address[] memory path,
        address _to
    ) internal {
        (address input, address output) = (path[0], path[1]);
        (address token0, ) = MiniswapLibrary.sortTokens(input, output);
        uint amountOut = amounts[1];
        (uint amount0Out, uint amount1Out) = input == token0
            ? (uint(0), amountOut)
            : (amountOut, uint(0));
        IMiniswapPair(MiniswapLibrary.pairFor(factory, input, output)).swap(
            amount0Out,
            amount1Out,
            to,
            new bytes(0)
        );
    }

    // 입금할 양이 정해졌을 때 출금될 양을 정해 swap해주는 함수
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        amounts = MiniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin);
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    // 출금할 양이 정해졌을 때 출금될 양을 정해 swap해주는 함수
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to
    ) external returns (uint[] memory amounts) {
        amounts = MiniswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax);
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            MiniswapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }
}
