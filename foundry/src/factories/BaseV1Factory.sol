// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

import {BaseV1Pair} from "src/AMM/BaseV1Pair.sol";

contract BaseV1Factory {
    /*//////////////////////////////////////////////////////////////
                           STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bool public isPaused;
    address public s_owner;
    address public s_pendingOwner;
    address public s_admin;

    uint256 public stableFee = 2000; // 0.2%
    uint256 public variableFee = 500; // 0.05%

    address internal _temp0;
    address internal _temp1;
    bool internal _temp;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/
    mapping(address => mapping(address => mapping(bool => address))) public s_getPair;
    address[] public allPairs;
    /// @notice Simplifed check if its a pair, given that `stable` flag might not be available in peripherals
    mapping(address => bool) public isPair;

    mapping(address => address) public s_protocolAddresses; // pair => protocol address
    address public s_spiritMaker;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint256);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        s_owner = msg.sender;
        isPaused = false;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair) {
        require(tokenA != tokenB, "BaseV1: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "BaseV1: ZERO_ADDRESS");
        require(s_getPair[token0][token1][stable] == address(0), "BaseV1: PAIR_EXISTS");

        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable));
        (_temp0, _temp1, _temp) = (token0, token1, stable);
        pair = address(new BaseV1Pair{salt: salt}());
        s_getPair[token0][token1][stable] = pair;
        s_getPair[token1][token0][stable] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        isPair[pair] = true;

        emit PairCreated(token0, token1, stable, pair, allPairs.length);
    }

    function setStableFee(uint256 _fee) external {
        require(msg.sender == s_owner);
        stableFee = _fee;
    }

    function setVariableFee(uint256 _fee) external {
        require(msg.sender == s_owner);
        variableFee = _fee;
    }

    function setOwner(address _owner) external {
        require(msg.sender == s_owner);
        s_pendingOwner = _owner;
    }

    function setAdmin(address _admin) external {
        require(msg.sender == s_owner);
        s_admin = _admin;
    }

    function acceptOwner() external {
        require(msg.sender == s_pendingOwner);
        s_owner = s_pendingOwner;
    }

    function setPause(bool _state) external {
        require(msg.sender == s_admin);
        isPaused = _state;
    }

    function setProtocolAddress(address _pair, address _protocolAddress) external {
        require(msg.sender == s_owner || msg.sender == s_admin || msg.sender == s_protocolAddresses[_pair]);
        s_protocolAddresses[_pair] = _protocolAddress;
    }

    function setSpiritMaker(address _spiritMaker) external {
        require(msg.sender == s_owner);
        s_spiritMaker = _spiritMaker;
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL VIEW/PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function getInitializable() external view returns (address, address, bool) {
        return (_temp0, _temp1, _temp);
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(BaseV1Pair).creationCode);
    }
}
