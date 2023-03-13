// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MiniswapPair is IMiniswapPair, MiniswapERC20 {
    // 숫자를 사용하는 라이브러리들 using 선언
    using SafeMath for uint
    // 112x112는 TWAP을 위한 data 저장에 사용된다.
    using UQ112x112 for uint224;

    // pair 컨트랙트를 배포한 factory 함수
    address public factory;
    // initialize() 함수로 생성과 동시에 초기화된 토큰 주소값
    address public token0;
    address public token1;

    // 자료구조에 저장된 토큰 1, 2의 값을 uint112로 표현한 두 개의 값
    uint112 private reserve0;
    uint112 private reserve1;
    // uint32로 표현한 블록 타임스탬프
    // 112 + 112 + 32의 자료형은 32byte로, 한번에 store할 수 있는 데이터의 양이다. 이를 통해 가스비가 절약된다.
    uint32 private blockTimestampLast;

    // public으로 선언된 토큰의 가격과 타임스탬프 연산의 값이다.
    // 이를 통해 외부 컨트랙트에서 price oracle을 사용할 수 있게 된다.
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;

    // 재진입을 방지하는 역할을 하는 modifier
    // application 레벨에서 상호배제를 구현해주기 위한 방법이다.
    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "Locked");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // 현재 자료구조에 저장되어있는 토큰의 양과 가장 최근 기록된 block timestamp를 가져올 수 있는 함수
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        // 토큰을 전송하는 함수, swap을 진행할 때 전송해야 할 token을 이 함수로 전송한다.
        // ERC20토큰의 전송 함수인 transfer을 selector로 하여 해당 토큰을 to 주소로 value 만큼 transfer한다.
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(bytes4(keccak256(bytes("transfer(address,uint256)")))), to, value);
        // 이 때 각 ERC20 토큰의 transfer 구조가 다르기때문에, false인 경우, success && 아무것도 오지 않는 경우, true && 반환 데이터가 false인 경우를 모두 고려하여
        // 해당되지 않는 경우에만 전송에 성공한 것으로 간주한다.
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Tx Failed");
    }
}

