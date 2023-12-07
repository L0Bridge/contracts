// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "../openzeppelin/token/ERC20/IERC20.sol";
import "../openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "../openzeppelin/access/Ownable.sol";
import "../interfaces/ILayerZeroEndpoint.sol";
import "../interfaces/IWETH.sol";

abstract contract FeeDonate is Ownable {
    using SafeERC20 for IERC20;
//    // gas Fee, gasFeeDonateMap[toChainID][fromTokenAddress]=nativeBalance
//    mapping(uint16 => mapping(address => uint256)) public gasFeeDonateMap;
//    // gasFeeDonateRate[toChainID][fromTokenAddress]=rate,  realRate = rate / 100
//    // rate default 0, mean rate = 100
//    mapping(uint16 => mapping(address => uint8)) gasFeeDonateRate;
//
//    // gas Fee, zroFeeDonateMap[toChainID][fromTokenAddress]=zroBalance
//    mapping(uint16 => mapping(address => uint256)) public zroFeeDonateMap;
//    // zroFeeDonateRate[toChainID][fromTokenAddress]=rate,  realRate = rate / 100
////    // rate default 0, mean rate = 100
////    mapping(uint16 => mapping(address => uint8)) zroFeeDonateRate;

    IWETH public weth;
    // bridge fee，bridgeFeeDonateMap[tokenAddress]=fromTokenBalance
    mapping(address => uint256) public bridgeFeeDonateMap;
    // bridgeFeeDonateRate[tokenAddress]=rate,  realRate = rate / 100
    // rate default 0, mean rate = 100
    mapping(address => uint8) bridgeFeeDonateRate;
//    // subsidyRecord[msg.sender][tokenAddress] = amount
//    mapping(address => mapping(address => uint256)) subsidyRecord;

    //---------------------------------------------------------------------------
    // EVENTS
//    event GasFeeDonate(uint16 toChainId, address token, uint256 amount);
//    event ZroFeeDonate(uint16 toChainId, address token, uint256 amount);
    event BridgeFeeDonate(address token, uint256 amount);

//    event ConsumeGasFeeDonate(uint16 toChainId, address token, uint256 subsidyAmount, address user);
//    event ConsumeZroFeeDonate(uint16 toChainId, address token, uint256 subsidyAmount, address user);
    event ConsumeBridgeFeeDonate(address token, uint256 subsidyAmount, address user);

    //---------------------------------------------------------------------------
    // external
//    function gasFeeDonate(uint16 toChainId, address token) external payable {
//        gasFeeDonateMap[toChainId][token] += msg.value;
//    }
//    function zroFeeDonate(uint16 toChainId, address token, uint256 amount) external {
//        (uint256 receivedAmount, ) = _receiveTokenAmount(false, token, amount);
//        zroFeeDonateMap[toChainId][token] += receivedAmount;
//    }
    function bridgeFeeDonate(address token, uint256 amount) external {
        (uint256 receivedAmount, ) = _receiveTokenAmount(false, token, amount);
        bridgeFeeDonateMap[token] += receivedAmount;
    }

//    function claimSubsidy(address token) external {
//        uint256 amount = subsidyRecord[msg.sender][token];
//        subsidyRecord[msg.sender][token] = 0;
//        IERC20(token).safeTransferFrom(address(this), msg.sender, amount);
//    }

    //---------------------------------------------------------------------------
    // internal
//    function consumeGasFeeDonate(uint16 toChainId, address token, uint256 subsidyAmount) internal {
//        if (subsidyAmount == 0) {
//            return;
//        }
//        gasFeeDonateMap[toChainId][token] -= subsidyAmount;
//        emit ConsumeGasFeeDonate(toChainId, token, subsidyAmount, msg.sender);
//    }
//
//    function consumeZroFeeDonate(uint16 toChainId, address token, uint256 subsidyAmount) internal {
//        if (subsidyAmount == 0) {
//            return;
//        }
//        zroFeeDonateMap[toChainId][token] -= subsidyAmount;
//        emit ConsumeZroFeeDonate(toChainId, token, subsidyAmount, msg.sender);
//    }

    function consumeBridgeFeeDonate(address token, uint256 subsidyAmount) internal {
        bridgeFeeDonateMap[token] -= subsidyAmount;
//        subsidyRecord[msg.sender][token] += subsidyAmount;
        emit ConsumeBridgeFeeDonate(token, subsidyAmount, msg.sender);
    }

//    // returns (bool payInZro, uint256 estimateFee, uint256 subsidyFee)
//    function getGasFeeSubsidy(ILayerZeroEndpoint layerZeroEndpoint, uint16 toChainId, address token, bytes memory payload, bytes memory adapterParams) internal returns(bool, uint256, uint256) {
//        if (gasFeeDonateMap[toChainId][token] >= msg.value) {
//            return (_getGasFeeNativeSubsidy(layerZeroEndpoint, toChainId, token, payload, adapterParams));
//        }
//        if (zroFeeDonateMap[toChainId][token] > 0) {
//            return (_getZroFeeNativeSubsidy(layerZeroEndpoint, toChainId, token, payload, adapterParams));
//        }
//        return (false, 0, 0);
//    }

    // returns (uint256 subsidyFee)
    function getBridgeFeeSubsidy(address token, uint256 bridgeFee) public view returns(uint256) {
        if (bridgeFeeDonateMap[token] == 0) {
            return 0;
        }
        uint256 needSubsidyAmount = bridgeFee;
        if (bridgeFeeDonateRate[token] != 0) {
            needSubsidyAmount = bridgeFee * bridgeFeeDonateRate[token] / 100;
        }
        if (bridgeFeeDonateMap[token] < needSubsidyAmount) {
            return 0;
        }
        return needSubsidyAmount;
    }

//    function _getZroFeeNativeSubsidy(ILayerZeroEndpoint layerZeroEndpoint, uint16 toChainId, address token, bytes memory payload, bytes memory adapterParams) internal returns(bool, uint256, uint256) {
//        (uint nativeFee, uint zroFee) = layerZeroEndpoint.estimateFees(toChainId, address(this), payload, true, adapterParams);
////        uint256 needSubsidyAmount = zroFee;
////        if (zroFeeDonateRate[toChainId][token] != 0) {
////            needSubsidyAmount = zroFee * zroFeeDonateRate[toChainId][token] / 100;
////        }
//        if (zroFeeDonateMap[toChainId][token] < zroFee) {
//            return (true, zroFee, 0);
//        }
//        return (true, zroFee, zroFee);
//    }
//
//    function _getGasFeeNativeSubsidy(ILayerZeroEndpoint layerZeroEndpoint, uint16 toChainId, address token, bytes memory payload, bytes memory adapterParams) internal returns(bool, uint256, uint256) {
//        (uint nativeFee, uint zroFee) = layerZeroEndpoint.estimateFees(toChainId, address(this), payload, false, adapterParams);
//        uint256 needSubsidyAmount = nativeFee;
//        if (gasFeeDonateRate[toChainId][token] != 0) {
//            needSubsidyAmount = nativeFee * gasFeeDonateRate[toChainId][token] / 100;
//        }
//        if (gasFeeDonateMap[toChainId][token] < needSubsidyAmount) {
//            return (false, nativeFee, 0);
//        }
//        return (false, nativeFee, needSubsidyAmount);
//    }

//    function _receiveTokenAmount(address token, uint256 amount) internal returns(uint256 receivedAmount) {
//        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
//        IERC20(fromTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
//        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
//        require(balanceAfter > balanceBefore, "valid amount");
//        receivedAmount = balanceAfter - balanceBefore;
//        return receivedAmount;
//    }

    function _receiveTokenAmount(bool isNative, address fromTokenAddress, uint256 amount) internal returns(uint256, uint256) {
        // CPToken from any chain can only be returned to which chain, and cannot be swindled
        uint256 balanceBefore = IERC20(fromTokenAddress).balanceOf(address(this));
        uint256 leftBalance = msg.value;
        if (isNative) {
            weth.deposit{value: amount}();
            leftBalance -= amount;
        } else {
            IERC20(fromTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        }
        uint256 balanceAfter = IERC20(fromTokenAddress).balanceOf(address(this));
        // check balance
        require(balanceAfter > balanceBefore, "123");
        uint256 receivedAmount = balanceAfter - balanceBefore;
        return (receivedAmount, leftBalance);
    }

    //---------------------------------------------------------------------------
    // Owner
//    function setGasFeeDonateRate(uint16 toChainId, address fromToken, uint8 rate) external onlyOwner {
//        require(rate <= 100);
//        gasFeeDonateRate[toChainId][fromToken] = rate;
//    }

    function setBridgeFeeDonateRate(address token, uint8 rate) external onlyOwner {
        require(rate <= 100);
        bridgeFeeDonateRate[token] = rate;
    }

}
