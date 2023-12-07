// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;
import "./CPToken.sol";
import "./openzeppelin/access/Ownable.sol";

contract TokenFactory is Ownable {

    function registerCPToken(uint16 srcChainId, address fromTokenAddress, string memory name, uint8 decimals) external returns(address) {
        CPToken newCPToken = new CPToken(msg.sender, srcChainId, fromTokenAddress, name, decimals);
        return address(newCPToken);
    }
}
