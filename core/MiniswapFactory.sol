// SPDX-License-Identifier: UNLICENSED
pragma solidity = 0.6.6;

import "../interfaces/IMiniswapFactory.sol";
import "./MiniswapPair.sol";

contract Factory is IMiniswapFactory {
    // token pair들을 저장하는 mapping
    mapping(address => mapping(address => address)) public override getPair;
    // token pair 컨트랙트 주소를 저장하는 array
    address[] public override allPairs;

    // pair 생성시 발생하는 이벤트, 이를 통해 온체인 이벤트를 트래킹할 수 있다.
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint
    );

    // 원래는 배포시에 _feeTo 주소를 세팅해주지만 프로토콜 피 기능을 구현하지 않을 것이기 때문에 설정하지 않음
    constructor() public {}

    // 페어를 생성하는 함수
    function createPair(
        address tokenA,
        address tokenB
    ) external override returns (address pair) {
        // 페어로 추가하고자 하는 토큰은 같은 토큰일 수 없다.
        require(tokenA != tokenB, "same token can't be pair");

        // 인자로 받은 두 토큰을 주소값의 크기 순서로 정렬한다.
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        // 둘 중 더 작은 token0이 0보다 커야 둘 다 유효한 토큰임을 증명할 수 있다.
        require(token0 != address(0), "0 address can't be pair");
        // 페어가 존재하지 않는다는 것을 확인한다.
        require(getPair[token0][token1] == address(0), "already exist pair");

        // pair 컨트랙트의 바이트코드를 가져와 변수에 담아준다.
        bytes memory bytecode = type(MiniswapPair).creationCode;
        // token0, token1의 abi 값을 가져다가 해싱하여 salt값으로 삼는다.
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        // create2 를 사용하여 새로운 pair pool 컨트랙트를 생성한다.
        // create 함수는 nonce값을 사용하기 때문에 주소를 예측할 수 없어 트랜잭션이 컨펌된 후에나 알 수 있다.
        // 그러나 create2 는 컨트랙트 주소, salt값, 생성될 컨트랙트의 바이트코드를 사용해 주소를 계산할 수 있기 때문에
        // 트랜잭션이 컨펌되기 전에 주소를 알고 적용할 수 있다.
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        // 미리 계산해놓은 주소의 pair 컨트랙트에 있는 initialize 함수를 실행한다.
        // 이 녀석은 해당 컨트랙트 내의 전역변수인 두 개의 토큰의 주소값을 초기화해주는 역할을 한다.
        IMiniswapPair(pair).initialize(token0, token1);

        // getPair 자료구조와 allPairs 자료구조에 pair 컨트랙트의 주소를 넣어준다.
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        // event emit
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
