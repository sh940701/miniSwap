// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./SafeMath.sol";

// 주소 크기순으로 정렬된 순서를 반환하는 함수
function sortTokens(
    address tokenA,
    address tokenB
) internal pure returns (address token0, address token1) {
    require(tokenA != tokenB);
    (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(token0 != address(0));
}

// pair contract의 주소를 계산해주는 함수. external call을 하는 것보다 가스비가 저렴하다고 한다.
function pairFor(
    address factory,
    address tokenA,
    address tokenB
) internal pure returns (address pair) {
    (address token0, address token1) = sortTokens(tokenA, tokenB);
    pair = address(
        uint(
            keccak256(
                abi.encodePacked(
                    hex"ff",
                    factory,
                    keccak256(abi.encodePacked(token0, token1)),
                    hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
                )
            )
        )
    );
}

// pair 컨트랙트의 자료구조에 담겨있는 토큰의 양을 정렬하여 반환하는 함수
function getReserves(
    address factory,
    address tokenA,
    address tokenB
) internal view returns (uint reserveA, uint reserveB) {
    (address token0, ) = sortTokens(tokenA, tokenB);
    (uint reserve0, uint reserve1, ) = IMiniswap(
        pairFor(factory, tokenA, tokenB)
    ).getReserves();
    (reserveA, reserveB) = tokenA == token0
        ? (reserve0, reserve1)
        : (reserve1, reserve0);
}

// 주어진 자산의 양에 대해서 동등한 가치의 다른 자산의 양을 반환하는 함수
// amountA : X = reserveA : reserveB 의 공식을 따르는 것이다.
function quote(
    uint amountA,
    uint reserveA,
    uint reserveB
) internal pure returns (uint amountB) {
    require(amountA > 0 && reserveA > 0 && reserveB > 0);
    amountB = amountA.mul(reserveB) / reserveA;
}

// 입금할 토큰의 양이 정해져있을 때, 수수료를 적용하여 출금할 토큰의 양을 반환하는 함수
function getAmountOut(
    uint amountIn,
    uint reserveIn,
    uint reserveOut
) internal pure returns (uint amountOut) {
    require(amountIn > 0 && reserveIn > 0 && reserveOut > 0);
    uint amountInWithFee = amountIn.mul(997);
    uint numerator = amountInWithFee.mul(reserveOut);
    uint denominator = reserveIn.mul(1000).add(amountInWithFee);
    amountOut = numerator / denominator;
}

// 출금할 토큰의 양이 정해져있을 때, 수수료를 적용하여 입금할 토큰의 양을 반환하는 함수
function getAmountIn(
    uint amountOut,
    uint reserveIn,
    uint reserveOut
) internal pure returns (uint amountIn) {
    require(amountOut > 0 && reserveIn > 0 && reserveOut > 0);
    uint numerator = reserveIn.mul(amountOut).mul(1000);
    uint denominator = reserveOut.sub(amountOut).mul(997);
    amountIn = (numerator / denominator).add(1);
}

function getAmountsOut(
    address factory,
    uint amountIn,
    address[] memory path
) internal view returns (uint[] memory amounts) {
    require(path.length >= 2);
    amounts = new uint[](path.length);
    amounts[0] = amountIn;
    for (uint i; i < path.length - 1; i++) {
        (uint reserveIn, uint reserveOut) = getReserves(
            factory,
            path[i],
            path[i + 1]
        );
        amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
    }
}

function getAmountsIn(
    address factory,
    uint amountOut,
    address[] memory path
) internal view returns (uint[] memory amounts) {
    require(path.length >= 2);
    amounts = new uint[](path.length);
    amounts[amounts.length - 1] = amountOut;
    for (uint i = path.length - 1; i > 0; i--) {
        (uint reserveIn, uint reserveOut) = getReserves(
            factory,
            path[i - 1],
            path[i]
        );
        amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
    }
}
