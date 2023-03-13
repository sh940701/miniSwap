// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract Factory {
    // token pair들을 저장하는 mapping
    mapping(address => mapping(address => address)) public getPair;
    // token pair 컨트랙트 주소를 저장하는 array
    address[] public allPairs;

    constructor()
}