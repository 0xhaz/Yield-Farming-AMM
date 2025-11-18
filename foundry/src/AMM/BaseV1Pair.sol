// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

import {IBaseV1Factory} from "src/interfaces/IBaseV1Factory.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {BaseV1Fees} from "src/AMM/BaseV1Fees.sol";
import {Math} from "src/libraries/Math.sol";
import {IBaseV1Callee} from "src/interfaces/IBaseV1Callee.sol";

/**
 * @title BaseV1Pair
 * @notice The base pair of pools, either stable or volatile
 */
contract BaseV1Pair {
    /*//////////////////////////////////////////////////////////////
                         GLOBAL STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    string public s_name;
    string public s_symbol;
    uint8 public constant DECIMALS = 18;

    /// @notice Used to denote stable or volatile pair, not immutable since construction happens in the initialize method for CREATE2 deterministic addresses
    bool public immutable i_stable;
    uint256 public s_fee;
    uint256 public s_totalSupply = 0;

    bytes32 internal DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 internal constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    uint256 internal constant MINIMUM_LIQUIDITY = 10 ** 3; // 1000

    address public immutable i_token0;
    address public immutable i_token1;
    address public immutable i_fees;
    address public immutable i_factory;

    // Capture oracle reading every 30 minutes
    uint256 constant PERIOD_SIZE = 1800;

    uint256 internal immutable i_decimals0;
    uint256 internal immutable i_decimals1;

    uint256 public s_reserve0;
    uint256 public s_reserve1;
    uint256 public s_blockTimestampLast;

    uint256 public s_reserve0CumulativeLast;
    uint256 public s_reserve1CumulativeLast;

    /// @notice Index0 and index1 are used to accumulate fees, this is split out from normal trades to keep the swap "clean"
    /// this further allows LP holders to easily claim fees for tokens they have staked
    uint256 public s_index0 = 0;
    uint256 public s_index1 = 0;

    /// @notice Structure to capture time period observations every 30 minutes, used for local oracles
    struct Observation {
        uint256 timestamp;
        uint256 reserve0Cumulative;
        uint256 reserve1Cumulative;
    }

    Observation[] public s_observations;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/
    mapping(address => uint256) public s_nonces;
    mapping(address => mapping(address => uint256)) public s_allowance;
    mapping(address => uint256) public s_balanceOf;

    /// @notice Position assigned to each LP to track their current index0 & index1 vs the global position
    mapping(address => uint256) public s_supplyIndex0;
    mapping(address => uint256) public s_supplyIndex1;

    /// @notice Tracks the amount of unclaimed, but claimable tokens off of fees for token0 and token1
    mapping(address => uint256) public s_claimable0;
    mapping(address => uint256) public s_claimable1;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Fees(address indexed sender, uint256 amount0, uint256 amount1);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 reserve0, uint256 reserve1);
    event Claim(address indexed sender, address indexed recipient, uint256 amount0, uint256 amount1);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        i_factory = msg.sender;
        (address _token0, address _token1, bool _stable) = IBaseV1Factory(msg.sender).getInitializable();
        (i_token0, i_token1, i_stable) = (_token0, _token1, _stable);
        i_fees = address(new BaseV1Fees(_token0, _token1, i_factory));
        if (_stable) {
            s_name =
                string(abi.encodePacked("StableV1 AMM - ", IERC20(_token0).symbol(), "/", IERC20(_token1).symbol()));
            s_symbol = string(abi.encodePacked("sAMM-", IERC20(_token0).symbol(), "/", IERC20(_token1).symbol()));
            s_fee = IBaseV1Factory(i_factory).stableFee();
        } else {
            s_name =
                string(abi.encodePacked("VolatileV1 AMM - ", IERC20(_token0).symbol(), "/", IERC20(_token1).symbol()));
            s_symbol = string(abi.encodePacked("vAMM-", IERC20(_token0).symbol(), "/", IERC20(_token1).symbol()));
            s_fee = IBaseV1Factory(i_factory).variableFee();
        }

        i_decimals0 = 10 ** IERC20(_token0).decimals();
        i_decimals1 = 10 ** IERC20(_token1).decimals();

        s_observations.push(Observation({timestamp: block.timestamp, reserve0Cumulative: 0, reserve1Cumulative: 0}));
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIER
    //////////////////////////////////////////////////////////////*/
    /// @notice Simple re-entrancy lock modifier
    uint256 internal unlocked = 1;

    modifier lock() {
        require(unlocked == 1, "BaseV1: LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function sample(address tokenIn, uint256 amountIn, uint256 points, uint256 window)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory _prices = new uint256[](points);
        uint256 length = s_observations.length - 1;
        uint256 i = length - (points * window);
        uint256 nextIndex = 0;
        uint256 index = 0;

        for (; i < length; i += window) {
            nextIndex = i + window;
            uint256 timeElapsed = s_observations[nextIndex].timestamp - s_observations[i].timestamp;
            uint256 _reserve0 =
                (s_observations[nextIndex].reserve0Cumulative - s_observations[i].reserve0Cumulative) / timeElapsed;
            uint256 _reserve1 =
                (s_observations[nextIndex].reserve1Cumulative - s_observations[i].reserve1Cumulative) / timeElapsed;
            _prices[index] = _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
            index++;
        }
        return _prices;
    }

    /// @notice The cumulative price using counterfactuals to save gas and avoid a call to sync
    function currentCumulativePrices()
        public
        view
        returns (uint256 reserve0Cumulative, uint256 reserve1Cumulative, uint256 blockTimestamp)
    {
        blockTimestamp = block.timestamp;
        reserve0Cumulative = s_reserve0CumulativeLast;
        reserve1Cumulative = s_reserve1CumulativeLast;

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) = getReserves();
        if (_blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint256 timeElapsed = blockTimestamp - _blockTimestampLast;
            reserve0Cumulative += _reserve0 * timeElapsed;
            reserve1Cumulative += _reserve1 * timeElapsed;
        }
    }

    function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) {
        _reserve0 = s_reserve0;
        _reserve1 = s_reserve1;
        _blockTimestampLast = s_blockTimestampLast;
    }

    function lastObservation() public view returns (Observation memory) {
        return s_observations[s_observations.length - 1];
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function updateFee() external {
        if (i_stable) {
            s_fee = IBaseV1Factory(i_factory).stableFee();
        } else {
            s_fee = IBaseV1Factory(i_factory).variableFee();
        }
    }

    function spiritMaker() external returns (address) {
        return IBaseV1Factory(i_factory).spiritMaker();
    }

    function protocol() external returns (address) {
        return IBaseV1Factory(i_factory).protocolAddresses(address(this));
    }

    /// @notice Claim accumulated but unclaimed fees (viewable via claimable0/1)
    function claimFees() external returns (uint256 claimed0, uint256 claimed1) {
        _updateFor(msg.sender);

        claimed0 = s_claimable0[msg.sender];
        claimed1 = s_claimable1[msg.sender];

        if (claimed0 > 0 || claimed1 > 0) {
            s_claimable0[msg.sender] = 0;
            s_claimable1[msg.sender] = 0;

            (claimed0, claimed1) = BaseV1Fees(i_fees).claimFeesFor(msg.sender, claimed0, claimed1);

            emit Claim(msg.sender, msg.sender, claimed0, claimed1);
        }
    }

    function transfer(address dst, uint256 amount) external returns (bool) {
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    function transferFrom(address src, address dst, uint256 amount) external returns (bool) {
        address spender = msg.sender;
        uint256 spenderAllowance = s_allowance[src][spender];

        if (spender != src && spenderAllowance != type(uint256).max) {
            uint256 newAllowance = spenderAllowance - amount;
            s_allowance[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    /// @notice This low-level function should be called from a contract which performs important safety checks
    /// standard uniswap V2 implementation
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint256 _reserve0, uint256 _reserve1) = (s_reserve0, s_reserve1); // gas savings
        uint256 _balance0 = IERC20(i_token0).balanceOf(address(this));
        uint256 _balance1 = IERC20(i_token1).balanceOf(address(this));
        uint256 _amount0 = _balance0 - _reserve0; // calculate the amounts being sent in
        uint256 _amount1 = _balance1 - _reserve1;

        uint256 _totalSupply = s_totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(_amount0 * _amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(_amount0 * _totalSupply / _reserve0, _amount1 * _totalSupply / _reserve1);
        }
        require(liquidity > 0, "BaseV1: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(_balance0, _balance1, _reserve0, _reserve1);

        emit Mint(msg.sender, _amount0, _amount1);
    }

    /// @notice This low-level function should be called from a contract which performs important safety checks
    /// standard uniswap V2 implementation
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint256 _reserve0, uint256 _reserve1) = (s_reserve0, s_reserve1); // gas savings
        (address _token0, address _token1) = (i_token0, i_token1);
        uint256 _balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 _balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 _liquidity = s_balanceOf[address(this)];

        uint256 _totalSupply = s_totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = _liquidity * _balance0 / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = _liquidity * _balance1 / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, "BaseV1: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), _liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        _balance0 = IERC20(_token0).balanceOf(address(this));
        _balance1 = IERC20(_token1).balanceOf(address(this));

        _update(_balance0, _balance1, _reserve0, _reserve1);

        emit Burn(msg.sender, amount0, amount1, to);
    }

    /// @notice This low-level function should be called from a contract which performs important safety checks
    /// standard uniswap V2 implementation
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external lock {
        require(!IBaseV1Factory(i_factory).isPaused(), "BaseV1: PAUSED");
        require(amount0Out > 0 || amount1Out > 0, "BaseV1: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint256 _reserve0, uint256 _reserve1) = (s_reserve0, s_reserve1);
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "BaseV1: INSSUFFICIENT_LIQUIDITY");

        uint256 _balance0;
        uint256 _balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            (address _token0, address _token1) = (i_token0, i_token1);
            require(to != _token0 && to != _token1, "BaseV1: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) IBaseV1Callee(to).hook(msg.sender, amount0Out, amount1Out, data); // callback, used for flash loans
            _balance0 = IERC20(_token0).balanceOf(address(this));
            _balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = _balance0 > _reserve0 - amount0Out ? _balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = _balance1 > _reserve1 - amount1Out ? _balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "BaseV1: INSUFFICIENT_INPUT_AMOUNT");
        {
            (address _token0, address _token1) = (i_token0, i_token1);

            if (amount0In > 0) _update0(amount0In / s_fee); // accrue fees for token0 and move them out of the pool
            if (amount1In > 0) _update1(amount1In / s_fee); // accrue fees for token1 and move them out of the pool

            // since we removed tokens, we need to reconfirm balances,
            // can also simply use previous balance - amountIn / 10_000, but doing balanceOf again as safety checks
            _balance0 = IERC20(_token0).balanceOf(address(this));
            _balance1 = IERC20(_token1).balanceOf(address(this));
            // The curve, either x3y+y3x for stable pools, or x*y for volatile pools
            require(_k(_balance0, _balance1) >= _k(_reserve0, _reserve1), "BaseV1: K");
        }

        _update(_balance0, _balance1, _reserve0, _reserve1);

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @notice Force balances to match reserves
    function skim(address to) external lock {
        (address _token0, address _token1) = (i_token0, i_token1);
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - s_reserve0);
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - s_reserve1);
    }

    /// @notice Force reserves to match balances
    function sync() external lock {
        _update(
            IERC20(i_token0).balanceOf(address(this)), IERC20(i_token1).balanceOf(address(this)), s_reserve0, s_reserve1
        );
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        s_allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        require(deadline >= block.timestamp, "BaseV1: EXPIRED");
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(s_name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, s_nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "BaseV1: INVALID_SIGNATURE");
        s_allowance[owner][spender] = value;

        emit Approval(owner, spender, value);
    }

    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256) {
        (uint256 _reserve0, uint256 _reserve1) = (s_reserve0, s_reserve1);
        amountIn -= amountIn / s_fee; // take out fee from amountIn
        return _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
    }

    /// @notice Gives the current twap price measured from amountIn * tokenIn gives amountOut
    function current(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        Observation memory _observation = lastObservation();
        (uint256 reserve0Cumulative, uint256 reserve1Cumulative,) = currentCumulativePrices();
        if (block.timestamp == _observation.timestamp) {
            _observation = s_observations[s_observations.length - 2]; // second last observation
        }

        uint256 timeElapsed = block.timestamp - _observation.timestamp;
        uint256 _reserve0 = (reserve0Cumulative - _observation.reserve0Cumulative) / timeElapsed;
        uint256 _reserve1 = (reserve1Cumulative - _observation.reserve1Cumulative) / timeElapsed;

        amountOut = _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
    }

    /// @notice As per `current`, however allows user configured granularity, up to the full window size
    function quote(address tokenIn, uint256 amountIn, uint256 granularity) external view returns (uint256 amountOut) {
        uint256[] memory _prices = sample(tokenIn, amountIn, granularity, 1);
        uint256 priceAverageCumulative;
        for (uint256 i = 0; i < _prices.length; i++) {
            priceAverageCumulative += _prices[i];
        }
        return priceAverageCumulative / granularity;
    }

    /// @notice Returns a memory set of twap prices
    function prices(address tokenIn, uint256 amountIn, uint256 points) external view returns (uint256[] memory) {
        return sample(tokenIn, amountIn, points, 1);
    }

    function metadata()
        external
        view
        returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool st, address t0, address t1)
    {
        return (i_decimals0, i_decimals1, s_reserve0, s_reserve1, i_stable, i_token0, i_token1);
    }

    function tokens() external view returns (address, address) {
        return (i_token0, i_token1);
    }

    function observationLength() external view returns (uint256) {
        return s_observations.length;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Accrued fees on token0
    function _update0(uint256 amount) internal {
        _safeTransfer(i_token0, i_fees, amount); // transfer the fees out of BaseV1Fees
        uint256 _ratio = amount * 1e18 / s_totalSupply; // how much per LP token?
        if (_ratio > 0) {
            s_index0 += _ratio;
        }

        emit Fees(msg.sender, amount, 0);
    }

    /// @notice Accrued fees on token1
    function _update1(uint256 amount) internal {
        _safeTransfer(i_token1, i_fees, amount); // transfer the fees out of BaseV1Fees
        uint256 _ratio = amount * 1e18 / s_totalSupply; // how much per LP token?
        if (_ratio > 0) {
            s_index1 += _ratio;
        }

        emit Fees(msg.sender, 0, amount);
    }

    /// @notice This function MUST be called on any balance changes, otherwise can be used to infinitely claim fees
    /// @dev Fees are segregated from core funds, so fees can never put liquidity at risk
    function _updateFor(address recipient) internal {
        uint256 _supplied = s_balanceOf[recipient]; // get LP balance of `recipient`
        if (_supplied > 0) {
            uint256 _supplyIndex0 = s_supplyIndex0[recipient]; // get last updated index0 for recipient
            uint256 _supplyIndex1 = s_supplyIndex1[recipient]; // get last updated index1 for recipient
            uint256 _index0 = s_index0; // get current global index0 for accumulated fees
            uint256 _index1 = s_index1; // get current global index1 for accumulated fees
            s_supplyIndex0[recipient] = _index0; // update user current position to global position
            s_supplyIndex1[recipient] = _index1; // update user current position to global position
            uint256 _delta0 = _index0 - _supplyIndex0; // see if there is any difference that need to be accrued
            uint256 _delta1 = _index1 - _supplyIndex1;
            if (_delta0 > 0) {
                uint256 _share = _supplied * _delta0 / 1e18; // add accrued difference for each token
                s_claimable0[recipient] += _share;
            }
            if (_delta1 > 0) {
                uint256 _share = _supplied * _delta1 / 1e18;
                s_claimable1[recipient] += _share;
            }
        } else {
            s_supplyIndex0[recipient] = s_index0; // new users are set to default global state
            s_supplyIndex1[recipient] = s_index1;
        }
    }

    /// @notice Update reserves and, on the first call per block, price cumulative data
    function _update(uint256 balance0, uint256 balance1, uint256 _reserve0, uint256 _reserve1) internal {
        uint256 blockTimestamp = block.timestamp;
        uint256 timeElapsed = blockTimestamp - s_blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            s_reserve0CumulativeLast += _reserve0 * timeElapsed;
            s_reserve1CumulativeLast += _reserve1 * timeElapsed;
        }

        Observation memory _point = lastObservation();
        /// @notice compare the last observation with current timestamp, if greater than 30 mins, record a new observation
        timeElapsed = blockTimestamp - _point.timestamp;
        if (timeElapsed > PERIOD_SIZE) {
            s_observations.push(
                Observation({
                    timestamp: blockTimestamp,
                    reserve0Cumulative: s_reserve0CumulativeLast,
                    reserve1Cumulative: s_reserve1CumulativeLast
                })
            );
        }
        s_reserve0 = balance0;
        s_reserve1 = balance1;
        s_blockTimestampLast = blockTimestamp;
        emit Sync(s_reserve0, s_reserve1);
    }

    function _mint(address dst, uint256 amount) internal {
        _updateFor(dst); // balances must be updated on mint/burn/transfer
        s_totalSupply += amount;
        s_balanceOf[dst] += amount;
        emit Transfer(address(0), dst, amount);
    }

    function _burn(address dst, uint256 amount) internal {
        _updateFor(dst); // balances must be updated on mint/burn/transfer
        s_totalSupply -= amount;
        s_balanceOf[dst] -= amount;
        emit Transfer(dst, address(0), amount);
    }

    function _transferTokens(address src, address dst, uint256 amount) internal {
        _updateFor(src); // update fee position for src
        _updateFor(dst); // update fee position for dst

        s_balanceOf[src] -= amount;
        s_balanceOf[dst] += amount;

        emit Transfer(src, dst, amount);
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _getAmountOut(uint256 amountIn, address tokenIn, uint256 _reserve0, uint256 _reserve1)
        internal
        view
        returns (uint256)
    {
        if (i_stable) {
            uint256 xy = _k(_reserve0, _reserve1);
            _reserve0 = _reserve0 * 1e18 / i_decimals0;
            _reserve1 = _reserve1 * 1e18 / i_decimals1;
            (uint256 reserveA, uint256 reserveB) = tokenIn == i_token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            amountIn = tokenIn == i_token0 ? amountIn * 1e18 / i_decimals0 : amountIn * 1e18 / i_decimals1;
            uint256 y = reserveB - Math._get_y(amountIn + reserveA, xy, reserveB);
            return y * (tokenIn == i_token0 ? i_decimals1 : i_decimals0) / 1e18;
        } else {
            (uint256 reserveA, uint256 reserveB) = tokenIn == i_token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
            return amountIn * reserveB / (reserveA + amountIn);
        }
    }

    function _k(uint256 x, uint256 y) internal view returns (uint256) {
        if (i_stable) {
            uint256 _x = x * 1e18 / i_decimals0;
            uint256 _y = y * 1e18 / i_decimals1;
            uint256 _a = (_x * _y) / 1e18;
            uint256 _b = ((_x * _x) / 1e18 + (_y * _y) / 1e18);
            return _a * _b / 1e18; // x3y + y3x >= k
        } else {
            return x * y; // xy >= k
        }
    }
}
