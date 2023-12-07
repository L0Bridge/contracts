// SPDX-License-Identifier: BUSL-1.1

pragma solidity >=0.5.0;

interface ITokenFactory {
    function registerCPToken(uint16 srcChainId, address fromTokenAddress, string memory name, uint8 decimals) external returns(address);
}
