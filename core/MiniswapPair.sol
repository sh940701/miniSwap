// SPDX-License-Identifier: UNLICENSED
pragma solidity = 0.6.6;

import "../interfaces/IMiniswapPair.sol";
import "./MiniswapERC20.sol";
import "../libraries/Math.sol";
import "../libraries/UQ112x112.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IMiniswapFactory.sol";

contract MiniswapPair is MiniswapERC20 {
    // 숫자를 사용하는 라이브러리들 using 선언
    using SafeMath for uint;
    // 112x112는 TWAP을 위한 data 저장에 사용된다.
    using UQ112x112 for uint224;

    // pair 컨트랙트를 배포한 factory 컨트랙트의 주소값
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
    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        // 토큰을 전송하는 함수, swap을 진행할 때 전송해야 할 token을 이 함수로 전송한다.
        // ERC20토큰의 전송 함수인 transfer을 selector로 하여 해당 토큰을 to 주소로 value 만큼 transfer한다.
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                bytes4(keccak256(bytes("transfer(address,uint256)"))),
                to,
                value
            )
        );
        // 이 때 각 ERC20 토큰의 transfer 구조가 다르기때문에, false인 경우, success && 아무것도 오지 않는 경우, true && 반환 데이터가 false인 경우를 모두 고려하여
        // 해당되지 않는 경우에만 전송에 성공한 것으로 간주한다.
        // 출처: https://ethereum.stackexchange.com/questions/137882/why-does-uniswap-v2-use-safetransfer-to-transfer-tokens
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Tx Failed"
        );
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() public {
        // pair 컨트랙트를 배포한 factory 컨트랙트의 주소값을 초기화 해준다.
        factory = msg.sender;
    }

    // pair 컨트랙트 배포시 실행되어 token0, token1의 주소값을 초기화해주는 함수
    function initialize(address _token0, address _token1) external {
        require(
            msg.sender == factory,
            "Pair contract only can deployed by factory contract"
        );
        token0 = _token0;
        token1 = _token1;
    }

    function _update(
        uint balance0,
        uint balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        // 2진수 -1은 나타낼 수 있는 모든 수가 1이다. 그러므로 uint112(-1)은 2진수에서 112개의 1이 나열되어 있는 것이다.
        // 그런데 solidity는 음수를 지원하지 않기 때문에 해당 숫자는 -1이 아닌 양수로 취급되고
        // 결국 uint112(-1)은 112bit에서 나타낼 수 있는 가장 큰 수를 의미하게 된다.
        // 이를 통해 require에서는 overflow를 확인할 수 있게 된다.
        require(
            balance0 <= uint112(-1) && balance1 <= uint112(-1)
        );

        // 블록의 timestamp를 uint32에 맞추어 저장해준다.
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);

        // timeElapsed는 경과된 시간을 의미한다. blockTimestamp는 블록이 변경될 때만 바뀌기 때문에
        // 경과된 시간이 0인지 아닌지를 확인하면 블록의 변경 여부를 알 수 있다.
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // UQ112.112는 정수부분에 112bits, 소수부분에 112bits를 저장하는 자료형이다.
            // 이러한 성질을 이용하여 현재 토큰 가격의 정수, 소수를 224bits에 담고, 32bits의 timeElapsed를 담으면 256bits의 data가 생성된다.
            // EVM에서는 기본적으로 32bytes 단위로 읽기, 쓰기 작업을 진행하기 때문에 data를 이렇게 다루면
            // 읽기, 쓰기 작업을 최소화하여 가스 비용을 줄일 수 있다.

            // 해당 데이터는 각각 두 토큰의 현재 가격(a토큰가격 / b토큰, b토큰가격 / a토큰)과 해당 시점의 timestamp 정보를 담고 있기 때문에
            // 이를 활용하여 블록 변경 이전 각 토큰의 가격 및 시간정보를 확인하고 TWAP 정보를 적용할 수 있게 된다.
            price0CumulativeLast +=
                uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) *
                timeElapsed;
            price1CumulativeLast +=
                uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) *
                timeElapsed;
        }

        // 아래에서는 연산 후 토큰의 양과 시간을 업데이트 해준다.
        // 이 때 블록이 달라진다면 blockTimestampLast가 업데이트 될 것이고, 그렇지 않다면 바뀌지 않게 된다.
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function mint(address to) external lock returns (uint liquidity) {
        // 자료구조에 저장되어있는 토큰양 가져오기
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        // 실제 반영되어있는 토큰양 가져오기
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));

        // 실제 토큰 양과 자료구조의 토큰양의 차이가 현재 풀에 입금된 토큰의 양이다.
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        uint _totalSupply = totalSupply;
        // 총 공급량이 0일 때(처음 유동성을 공급하는 경우이다.)
        if (_totalSupply == 0) {
            // 이 경우 liquidity는 두 토큰의 곱에 루트를 한 값에서 1000을 뺀 값이다.
            // 이에 대한 설명은 백서에 기재되어있다.
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(10 ** 3);
            _mint(address(0), 10 ** 3);
        } else {
            // 이미 풀이 존재할 때, liquidity는 각 토큰의 새로 공급한 양 / 기존 보유량 * 총 공급량 중 작은값이 된다.
            liquidity = Math.min(
                amount0.mul(_totalSupply) / _reserve0,
                amount1.mul(_totalSupply)
            );
        }
        require(liquidity > 0, "liquidity can not be Zero");
        // to 주소에게 liquidity만큼의 토큰을 발급해준다.
        _mint(to, liquidity);

        // 현재 pair 컨트랙트의 토큰 보유량을 업데이트해준다.
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(
        address to
    ) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        address _token0 = token0;
        address _token1 = token1;

        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        uint _totalSupply = totalSupply;
        amount0 = liquidity.mul(balance0) / _totalSupply;
        amount1 = liquidity.mul(balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "pair 1 error");

        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);

        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint amount0Out, uint amount1Out, address to) external lock {
        require(amount0Out > 0 || amount1Out > 0, "pair 2 error");
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "pair 3 error");

        uint balance0;
        uint balance1;
        {
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1);

            // token0이 출금되어야(token1이 입금된)하는 경우
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            // token1이 출금되어야(token0이 입금된)하는 경우
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);

            // 둘 중 하나는 나갔을테니, 그 balance를 가져오자
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }

        // token0이 나갔으면 token1이, token1이 나갔으면 token0이 들어오겠지? 여기선 그 양을 계산해준다.
        uint amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;
        require(amount0In > 0 || amount1In > 0, "pair 4 error");

        {
            // 수수료 0.3%를 제한 금액을 구하여 require문으로 수수료를 지불할 수 있는지 여부를 확인한다.
            uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
            require(
                balance0Adjusted.mul(balance1Adjusted) >=
                uint(_reserve0).mul(_reserve1).mul(1000 ** 2)
                , "pair 5 error"
            );

            _update(balance0, balance1, _reserve0, _reserve1);
            emit Swap(
                msg.sender,
                amount0In,
                amount1In,
                amount0Out,
                amount1Out,
                to
            );
        }
    }

    function skim(address to) external lock {
        address _token0 = token0;
        address _token1 = token1;
        _safeTransfer(
            _token0,
            to,
            IERC20(_token0).balanceOf(address(this)).sub(reserve0)
        );
        _safeTransfer(
            _token1,
            to,
            IERC20(_token1).balanceOf(address(this)).sub(reserve1)
        );
    }

    function sync() external lock {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
}
