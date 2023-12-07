// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./openzeppelin/utils/math/SafeMath.sol";
import "./openzeppelin/security/ReentrancyGuard.sol";
import "./openzeppelin/token/ERC20/IERC20.sol";
import "./openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ILayerZeroReceiver.sol";
import "./interfaces/ILayerZeroEndpoint.sol";
import "./interfaces/ILayerZeroUserApplicationConfig.sol";
//import "./CPToken.sol";
import "./interfaces/ITokenFactory.sol";
import "./interfaces/ICPToken.sol";
import "./function/FeeDonate.sol";
import "./function/ExcessivelySafeCall.sol";

contract Bridge is FeeDonate, ILayerZeroReceiver, ILayerZeroUserApplicationConfig, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using ExcessivelySafeCall for address;
    struct LzTxObj {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;
    }

    struct BridgeParam {
        uint16 toChainId;
        bytes fromToken;
        bytes to;
        uint256 amount;
        bytes dstCallData;
    }

    //---------------------------------------------------------------------------
    // type
    uint8 TypeBridge = 0;
    uint8 TypeReturnBack = 1;
    uint8 TypeBridgeCPToken = 2;
    //---------------------------------------------------------------------------
    uint64 public nonce = 0;
    // 100/1000000 = 0.0001 = 0.01%, max:1%
    // If there is a fixed fee, the fee will not be calculated using the defaultBridgeFee
    uint16 public defaultBridgeFee = 100;
    uint16 public maxDefaultBridgeFee = 10000;
    // The fixed bridge fee is not unlimited and cannot exceed the fee calculated using the maxDefaultBridgeFee
    mapping(address => uint256) public fixedBridgeFee;

    //---------------------------------------------------------------------------
    // srcChainNonceMap[srcChainId][nonce] = 0/1
    mapping(uint16 => mapping(uint64 => uint8)) public srcChainNonceMap;
    // lZeroNonceMap[srcChainId][_srcAddress][nonceLZero] = 1/0
    mapping(uint16 => mapping(bytes => mapping(uint64 => uint8))) public lZeroNonceMap;
    // bridgeFromTokenAndCPTokenMapCache[srcChainId][fromTokenAddress] = cpTokenAddress
    mapping(uint16 => mapping(bytes => address)) public bridgeFromTokenAndCPTokenMapCache;
    // cpAndRealTokenMap[cpTokenAddress] = currentTokenAddress
    mapping(address => address) public cpAndRealTokenMap;
    // notMappedCPAndFromTokenMap[cpTokenAddress] = fromToken
    mapping(address => bytes) public notMappedCPAndFromTokenMap;
    // cpTokenMap[tokenAddress] = CPTokenAddress
    mapping(address => address) public cpTokenMap;
    // cpTokenBetweenTwoChainMap[toChainId][cpTokenAddress] = toChainCPTokenBytes
    mapping(uint16 => mapping(address => bytes)) public cpTokenBetweenTwoChainMap;
    // tokenPoolMap[tokenAddress] = balance
    mapping(address => uint256) public tokenPoolMap;
    // daoBridgeFeeMap[tokenAddress] = balance
    mapping(address => uint256) public daoBridgeFeeMap;
    // lpLiquidityMap[lpTokenAddress] = real token balance
    mapping(address => uint256) public lpLiquidityMap;
    // lpTokenMap[tokenAddress] = lpTokenAddress
    mapping(address => address) public lpTokenMap;
    // bridgeFromTokenRelation[srcChainId][fromTokenBytes] = toTokenAddress
    mapping(uint16 => mapping(bytes => address)) public bridgeFromTokenRelation;
    // bridgeToTokenRelation[toChainId][fromTokenBytes] = toTokenBytes
    mapping(uint16 => mapping(bytes => bytes)) public bridgeToTokenRelation;
    //---------------------------------------------------------------------------
    // VARIABLES
    ILayerZeroEndpoint public immutable layerZeroEndpoint;
    ITokenFactory public tokenFactory;
    uint16 public currentLZeroChainId;
    // Record toChainID and remote address and local address
    // bridgeLookup[toChainID] = remote+local
    mapping(uint16 => bytes) public bridgeLookup;
    mapping(uint16 => mapping(uint8 => uint256)) public gasLookup;
    // bridge fee
    uint8 public liquidityFeeRate;
    uint8 public daoFeeRate;

    //---------------------------------------------------------------------------
    // EVENTS
    event SendMsg(uint8 msgType, uint64 nonce);

    constructor(address _layerZeroEndpoint, address _tokenFactory, uint16 _currentLZeroChainId, address _weth) {
        // _weth can be setBridge real weth, If the current chain does not support weth, such as bsc, you only need to set 0 address
        require(_layerZeroEndpoint != address(0x0));
        layerZeroEndpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
        tokenFactory = ITokenFactory(_tokenFactory);
        currentLZeroChainId = _currentLZeroChainId;
        weth = IWETH(_weth);
    }

    receive() external payable {
        assert(msg.sender == address(weth)); // only accept ETH via fallback from the WETH contract
    }

    //---------------------------------------------------------------------------
    // nonblockingLzReceive
    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;
    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload, bytes _reason);
    event RetryMessageSuccess(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes32 _payloadHash);
    function _storeFailedMessage(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload,
        bytes memory _reason
    ) internal virtual {
        failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(_payload);
        emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, _reason);
    }
    function nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) public {
        // only internal transaction
        require(msg.sender == address(this), "NonblockingLzApp: caller must be LzApp");
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload, true);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload,
        bool _executeCallBack
    ) internal nonReentrant {
        // only internal transaction
        require(msg.sender == address(this), "NonblockingLzApp: caller must be LzApp");
        uint8 actionType;
        assembly {
            actionType := mload(add(_payload, 32))
        }
        _requireValidNonce(_srcChainId, _srcAddress, _nonce);

        if (actionType == TypeBridge) {
            _receiveBridgeAction(_srcChainId, _payload, _executeCallBack);
        } else if (actionType == TypeReturnBack) {
            _receiveReturnBackAction(_srcChainId, _payload);
        } else if (actionType == TypeBridgeCPToken) {
            _receiveBridgeCPTokenAction(_srcChainId, _payload);
        }
    }

    function retryMessage(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bool _executeCallBack,
        bytes calldata _payload
    ) external {
        // assert there is message to retry
        bytes32 payloadHash = failedMessages[_srcChainId][_srcAddress][_nonce];
        require(payloadHash != bytes32(0), "NonblockingLzApp: no stored message");
        require(keccak256(_payload) == payloadHash, "NonblockingLzApp: invalid payload");
        // clear the stored message
        failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);
        // execute the message. revert if it fails again
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload, _executeCallBack);
        emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, payloadHash);
    }

    //---------------------------------------------------------------------------
    // EXTERNAL functions
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override {
        // just support EVM
        require(msg.sender == address(layerZeroEndpoint), "118");
        require(
            _srcAddress.length == bridgeLookup[_srcChainId].length && bridgeLookup[_srcChainId].length > 0 && keccak256(_srcAddress) == keccak256(bridgeLookup[_srcChainId]),
            "119"
        );
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(this.nonblockingLzReceive.selector, _srcChainId, _srcAddress, _nonce, _payload)
        );
        if (!success) {
            _storeFailedMessage(_srcChainId, _srcAddress, _nonce, _payload, reason);
        }
    }

    //---------------------------------------------------------------------------
    // Internal functions
    function _receiveBridgeAction(uint16 _srcChainId, bytes memory _payload, bool _executeCallBack) internal {
        (, bytes memory fromToken, bytes memory toToken, bytes memory to, uint64 nonceSrc, uint256 amount, bool isNative, bytes memory callData) = abi.decode(_payload, (uint8, bytes, bytes, bytes, uint64, uint256, bool, bytes));
        address toTokenAddress = _recoveryAddress(toToken);
        address toAddress = _recoveryAddress(to);

        // require and use valid nonce
        _requireValidSrcNonce(_srcChainId, nonceSrc);

        if (toTokenAddress == address(0x0) || cpTokenMap[toTokenAddress] == address(0x0) || bridgeFromTokenRelation[_srcChainId][fromToken] != toTokenAddress) {
            // 1. not set to token; 2. not set trust map; 3. bridgeFromTokenRelation not match or not set
            // mint tmp CPToken, just can return back to source chain, can not bridge to other chain
            _mintNotMappedCPToken(_srcChainId, fromToken, toAddress, amount);
        } else if (tokenPoolMap[toTokenAddress] < amount) {
            // less liquidity
            _mintCPToken(toTokenAddress, toAddress, amount);
        } else {
            _returnToken(isNative, toTokenAddress, toAddress, amount);
        }
        if (!_executeCallBack || callData.length == 0) {
            return;
        }
        toAddress.call{value: 0}(callData);
    }

    function _receiveReturnBackAction(uint16 _srcChainId, bytes memory _payload) internal {
        (, bytes memory to, bytes memory toToken, uint64 nonceSrc, uint256 amount, bool isNative) = abi.decode(_payload, (uint8, bytes, bytes, uint64, uint256, bool));
        address toAddress = _recoveryAddress(to);
        address toTokenAddress = _recoveryAddress(toToken);

        // require and use valid nonce
        _requireValidSrcNonce(_srcChainId, nonceSrc);

        if (tokenPoolMap[toTokenAddress] < amount) {
            _addLiquidity(toTokenAddress, toAddress, amount);
        } else {
            _returnToken(isNative, toTokenAddress, toAddress, amount);
        }
    }

    function _receiveBridgeCPTokenAction(uint16 _srcChainId, bytes memory _payload) internal {
        (, bytes memory to, bytes memory srcCPtoken, bytes memory currentCPtoken, uint64 nonceSrc, uint256 amount) = abi.decode(_payload, (uint8, bytes, bytes, bytes, uint64, uint256));
        address toAddress = _recoveryAddress(to);
        address currentCPtokenAddress = _recoveryAddress(currentCPtoken);
        require(_compareBytes(cpTokenBetweenTwoChainMap[_srcChainId][currentCPtokenAddress], srcCPtoken), "117");
        // require and use valid nonce
        _requireValidSrcNonce(_srcChainId, nonceSrc);

        // mint cpToken
        ICPToken(currentCPtokenAddress).mint(amount, toAddress);
    }

    function _compareBytes(bytes memory a, bytes memory b) internal pure returns(bool){
        if (a.length != b.length) {
            return false;
        }
        for(uint i = 0; i < a.length; ++i) {
            if(a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    function _requireValidSrcNonce(uint16 _srcChainId, uint64 nonceSrc) internal {
        require(srcChainNonceMap[_srcChainId][nonceSrc] == 0, "120");
        // use nonce
        srcChainNonceMap[_srcChainId][nonceSrc] = 1;
    }

    function _requireValidNonce(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce) internal {
        require(lZeroNonceMap[_srcChainId][_srcAddress][_nonce] == 0, "121");
        // use nonceLZero
        lZeroNonceMap[_srcChainId][_srcAddress][_nonce] = 1;
    }

    function _mintNotMappedCPToken(uint16 _srcChainId, bytes memory fromToken, address to, uint256 amount) internal {
        // need create token for user
        ICPToken cpToken = ICPToken(_getAndCreateNotMappedCPToken(_srcChainId, fromToken));
        // mint cpToken
        cpToken.mint(amount, to);
    }

    function _mintCPToken(address toTokenAddress, address to, uint256 amount) internal {
        // toTokenAddress must have trusted CPToken
        ICPToken cpToken = ICPToken(cpTokenMap[toTokenAddress]);
        // mint cpToken
        cpToken.mint(amount, to);
    }

    function _returnToken(bool isNative, address tokenAddress, address to, uint256 amount) internal {
        uint256 balanceBefore = IERC20(tokenAddress).balanceOf(address(this));
        // calculate bridge fee
        uint256 bridgeFee = getBridgeFee(tokenAddress, amount);
        uint256 bridgeFeeSubsidy = getBridgeFeeSubsidy(tokenAddress, bridgeFee);
        consumeBridgeFeeDonate(tokenAddress, bridgeFeeSubsidy);
        // update lp liquidity
        uint256 liquidityBridgeFee = bridgeFee * liquidityFeeRate / 100;
        lpLiquidityMap[lpTokenMap[tokenAddress]] += liquidityBridgeFee;

        uint256 realSend = amount - bridgeFee + bridgeFeeSubsidy;

        tokenPoolMap[tokenAddress] -= (amount - liquidityBridgeFee);
        // record bridge fee
        daoBridgeFeeMap[tokenAddress] += (bridgeFee - liquidityBridgeFee);

        _safeTransfer(isNative, balanceBefore, tokenAddress, to, realSend);
    }

    function _safeTransfer(bool isNative, uint256 balanceBefore, address tokenAddress, address to, uint256 sendAmount) internal {
        if (isNative && address(weth) == tokenAddress) {
            // is native bridge and target chain had weth
            weth.withdraw(sendAmount);
            payable(to).transfer(sendAmount);
        } else {
            IERC20(tokenAddress).safeTransfer(to, sendAmount);
        }

        uint256 balanceAfter = IERC20(tokenAddress).balanceOf(address(this));
        require(balanceAfter >= balanceBefore || balanceBefore - balanceAfter <= sendAmount, "115");
    }

    function _recoveryAddress(bytes memory bytesAddr) internal pure returns(address) {
        //        require(bytesAddr.length == 20, "Invalid bytes length");
        if (bytesAddr.length != 20) {
            return address(0x0);
        }
        address addr;
        assembly {
            addr := mload(add(bytesAddr, 20))
        }
        return addr;
    }

    function _getAndCreateNotMappedCPToken(uint16 srcChainId, bytes memory fromToken) internal returns(address) {
        if (bridgeFromTokenAndCPTokenMapCache[srcChainId][fromToken] != address(0x0)) {
            return bridgeFromTokenAndCPTokenMapCache[srcChainId][fromToken];
        }
        address fromTokenAddress = address(0x0);
        if (fromToken.length == 20) {
            fromTokenAddress = _recoveryAddress(fromToken);
        }
        address cpTokenAddress = _registerCPToken(srcChainId, fromTokenAddress, "CP_Token", 18);
        bridgeFromTokenAndCPTokenMapCache[srcChainId][fromToken] = cpTokenAddress;
        notMappedCPAndFromTokenMap[cpTokenAddress] = fromToken;
        return cpTokenAddress;
    }

    function _registerCPToken(uint16 srcChainId, address fromTokenAddress, string memory name, uint8 decimals) internal returns(address) {
        //        CPToken newCPToken = new CPToken(srcChainId, fromTokenAddress, name, decimals);
        ICPToken newCPToken = ICPToken(tokenFactory.registerCPToken(srcChainId, fromTokenAddress, name, decimals));
        return address(newCPToken);
    }

    //---------------------------------------------------------------------------
    // LOCAL CHAIN FUNCTIONS
    function bridgeNative(BridgeParam memory bridgeParam, LzTxObj memory adapterParams) payable external nonReentrant {
        (uint256 realBridgeAmount, uint256 leftBalance) = _prepareBridge(true, bridgeParam.fromToken, bridgeParam.amount);

        require(_recoveryAddress(bridgeParam.fromToken) == address(weth), "122");

        // send message
        _callSend(leftBalance, bridgeParam.toChainId, TypeBridge, adapterParams, abi.encode(TypeBridge, bridgeParam.fromToken, bridgeToTokenRelation[bridgeParam.toChainId][bridgeParam.fromToken], bridgeParam.to, _getNextNonce(), realBridgeAmount, true, bridgeParam.dstCallData));
    }

    function bridge(BridgeParam memory bridgeParam, LzTxObj memory adapterParams) payable external nonReentrant {
        (uint256 realBridgeAmount, uint256 leftBalance) = _prepareBridge(false, bridgeParam.fromToken, bridgeParam.amount);

        // send message
        _callSend(leftBalance, bridgeParam.toChainId, TypeBridge, adapterParams, abi.encode(TypeBridge, bridgeParam.fromToken, bridgeToTokenRelation[bridgeParam.toChainId][bridgeParam.fromToken], bridgeParam.to, _getNextNonce(), realBridgeAmount, false, bridgeParam.dstCallData));
    }

    function bridgeCPToken(uint16 toChainId, bytes memory cpToken, bytes memory to, uint256 amount, LzTxObj memory lzTxParams) payable external nonReentrant {
        address cpTokenAddress = _recoveryAddress(cpToken);
        // check bridge
        require(cpTokenBetweenTwoChainMap[toChainId][cpTokenAddress].length != 0, "114");
        // destroy cp token
        ICPToken(cpTokenAddress).burn(amount, msg.sender);
        // send message
        bytes memory payload = abi.encode(TypeBridgeCPToken, to, cpToken, cpTokenBetweenTwoChainMap[toChainId][cpTokenAddress], _getNextNonce(), amount);
        _callSend(msg.value, toChainId, TypeBridgeCPToken, lzTxParams, payload);
    }

    function returnBack(bool isNative, uint16 toChainId, address cpTokenAddress, bytes memory to, uint256 amount, LzTxObj memory lzTxParams) payable external nonReentrant {
        bytes memory fromToken = notMappedCPAndFromTokenMap[cpTokenAddress];
        require(bridgeFromTokenAndCPTokenMapCache[toChainId][fromToken] == cpTokenAddress, "100");
        //        require(!isNative || fromTokenAddress == address(weth), "101");
        // destroy cp token
        ICPToken(cpTokenAddress).burn(amount, msg.sender);

        // send message
        bytes memory payload = abi.encode(TypeReturnBack, to, fromToken, _getNextNonce(), amount, isNative);
        //        bytes memory lzTxParamBuilt = _txParamBuilder(toChainId, TypeReturnBack, lzTxParams);
        _callSend(msg.value, toChainId, TypeReturnBack, lzTxParams, payload);
    }

    // In which chain the pool added can only be proposed in this chain
    // Not recommended for normal users
    function addLiquidityNative(uint256 amount) payable external nonReentrant {
        weth.deposit{value: amount}();
        _addLiquidity(address(weth), msg.sender, amount);
        tokenPoolMap[address(weth)] += amount;
    }

    function addLiquidity(address tokenAddress, uint256 amount) external nonReentrant {
        (uint256 receivedAmount, ) = _receiveTokenAmount(false, tokenAddress, amount);
        _addLiquidity(tokenAddress, msg.sender, receivedAmount);
        tokenPoolMap[tokenAddress] += amount;
    }

    function removeLiquidity(bool isNative, address tokenAddress, uint256 amount) external nonReentrant {
        require(!isNative || tokenAddress == address(weth), "103");
        uint256 balanceBefore = IERC20(tokenAddress).balanceOf(address(this));

        // forbid rebase reduce token
        require(tokenPoolMap[tokenAddress] <= balanceBefore, "104");

        address lpToken = lpTokenMap[tokenAddress];
        require(lpToken != address(0x0), "105");
        // calculate token amount
        uint256 removeAmount = lpLiquidityMap[lpToken] * amount / ICPToken(lpToken).totalSupply();

        // destroy cp token
        ICPToken(lpToken).burn(amount, msg.sender);
        // remove lp liquidity
        lpLiquidityMap[lpToken] -= removeAmount;
        // return token
        if (tokenPoolMap[tokenAddress] >= removeAmount) {
            tokenPoolMap[tokenAddress] -= removeAmount;

            _safeTransfer(isNative, balanceBefore, tokenAddress, msg.sender, removeAmount);
        } else {
            // return CPToken
            // need create token for user
            require(cpTokenMap[tokenAddress] != address(0x0), "107");
            ICPToken cpToken = ICPToken(cpTokenMap[tokenAddress]);
            // mint cpToken
            cpToken.mint(removeAmount, msg.sender);
        }
    }

    function removeCPToken(bool isNative, address cpTokenAddress, uint256 amount) external nonReentrant {
        // must be registered token
        address tokenAddress = cpAndRealTokenMap[cpTokenAddress];
        require(tokenAddress != address(0x0), "112");
        require(!isNative || tokenAddress == address(weth), "108");
        uint256 balanceBefore = IERC20(tokenAddress).balanceOf(address(this));
        // forbid rebase reduce token
        require(tokenPoolMap[tokenAddress] <= balanceBefore, "109");
        require(tokenPoolMap[tokenAddress] >= amount, "110");

        // destroy cp token
        ICPToken(cpTokenAddress).burn(amount, msg.sender);

        // remove CP liquidity
        _returnToken(isNative, tokenAddress, msg.sender, amount);
    }

    //---------------------------------------------------------------------------
    // View functions
    function getBridgeFee(address tokenAddress, uint256 amount) public view returns(uint256) {
        uint256 fee = fixedBridgeFee[tokenAddress];
        if (fee == 0) {
            fee = amount * defaultBridgeFee / 1000000;
        } else if (fee > amount * maxDefaultBridgeFee / 1000000) {
            fee = amount * maxDefaultBridgeFee / 1000000;
        }
        if (fee == 0) {
            // Fee must be charged
            fee = 1;
        }
        return fee;
    }

    //---------------------------------------------------------------------------
    // INTERNAL functions
    function _prepareBridge(bool isNative, bytes memory fromToken, uint256 amount) internal returns(uint256 receivedAmount, uint256 leftBalance) {
        address fromTokenAddress = _recoveryAddress(fromToken);
        require(fromTokenAddress != address(0x0), "116");
        (receivedAmount, leftBalance) = _receiveTokenAmount(isNative, fromTokenAddress, amount);

        // add into liquidity
        tokenPoolMap[fromTokenAddress] += receivedAmount;
        return (receivedAmount, leftBalance);
    }

    function _addLiquidity(address tokenAddress, address toAddress, uint256 amount) internal {
        require(lpTokenMap[tokenAddress] != address(0x0), "113");
        ICPToken lpToken = ICPToken(lpTokenMap[tokenAddress]);
        uint256 mintAmount = amount;
        if (lpToken.totalSupply() != 0) {
            // not first supply
            mintAmount = amount * lpToken.totalSupply() / lpLiquidityMap[address(lpToken)];
        }
        // mint cpToken
        lpToken.mint(mintAmount, toAddress);
        // lpLiquidityMap
        lpLiquidityMap[address(lpToken)] += amount;
    }

    function _getNextNonce() internal returns(uint64) {
        nonce += 1;
        return nonce;
    }

    function _txParamBuilderType1(uint256 gasAmount) internal pure returns (bytes memory) {
        uint16 txType = 1;
        return abi.encodePacked(txType, gasAmount);
    }

    function _txParamBuilderType2(uint256 gasAmount, uint256 dstNativeAmount, bytes memory dstNativeAddr) internal pure returns (bytes memory) {
        uint16 txType = 2;
        return abi.encodePacked(txType, gasAmount, dstNativeAmount, dstNativeAddr);
    }

    function _txParamBuilder(uint16 toChainId, uint8 actionType, LzTxObj memory lzTxParams) internal view returns (bytes memory) {
        bytes memory adapterParams;
        address dstNativeAddr;
        {
            bytes memory dstNativeAddrBytes = lzTxParams.dstNativeAddr;
            assembly {
                dstNativeAddr := mload(add(dstNativeAddrBytes, 20))
            }
        }
        uint256 totalGas = gasLookup[toChainId][actionType].add(lzTxParams.dstGasForCall);
        if (lzTxParams.dstNativeAmount > 0 && dstNativeAddr != address(0x0)) {
            adapterParams = _txParamBuilderType2(totalGas, lzTxParams.dstNativeAmount, lzTxParams.dstNativeAddr);
        } else {
            adapterParams = _txParamBuilderType1(totalGas);
        }
        return adapterParams;
    }

    function _callSend(uint256 leftBalance, uint16 toChainId, uint8 actionType, LzTxObj memory lzTxParams, bytes memory payload) internal  {
        bytes memory lzTxParamBuilt = _txParamBuilder(toChainId, actionType, lzTxParams);
        layerZeroEndpoint.send{value: leftBalance}(toChainId, bridgeLookup[toChainId], payload, payable(msg.sender), address(this), lzTxParamBuilt);
        emit SendMsg(actionType, layerZeroEndpoint.getOutboundNonce(toChainId, address(this)) + 1);
    }

    //---------------------------------------------------------------------------
    // DAO config set
    function setDefaultBridgeFee(uint16 _defaultBridgeFee) external onlyOwner {
        // min: 1/1000000 = 0.000001 = 0.0001%
        // max: 10000/1000000 = 0.01 = 1%
        require(_defaultBridgeFee <= maxDefaultBridgeFee);
        defaultBridgeFee = _defaultBridgeFee;
    }

    function setFixedBridgeFee(address tokenAddress, uint256 fee) external onlyOwner {
        fixedBridgeFee[tokenAddress] = fee;
    }

    function registerTokenMap(address tokenAddress, string memory cpTokenName, string memory lpTokenName, uint8 decimals) external onlyOwner {
        require(cpTokenMap[tokenAddress] == address(0x0));
        // CP
        address cpToken = _registerCPToken(currentLZeroChainId, tokenAddress, cpTokenName, decimals);
        cpAndRealTokenMap[cpToken] = tokenAddress;
        cpTokenMap[tokenAddress] = cpToken;
        // LP
        address lpToken = _registerCPToken(currentLZeroChainId, tokenAddress, lpTokenName, 18);
        lpTokenMap[tokenAddress] = lpToken;
    }

    function registerBridgeFrom(uint16 fromChainId, bytes calldata fromToken, address toTokenAddress) external onlyOwner {
        require(bridgeFromTokenRelation[fromChainId][fromToken] == address(0x0));
        bridgeFromTokenRelation[fromChainId][fromToken] = toTokenAddress;
    }

    function registerBridgeTo(uint16 toChainId, bytes memory fromTokenBytes, bytes memory toChainTokenBytes) external onlyOwner {
        require(bridgeToTokenRelation[toChainId][fromTokenBytes].length == 0);
        bridgeToTokenRelation[toChainId][fromTokenBytes] = toChainTokenBytes;
    }

    function registerBridgeCPTo(uint16 toChainId, address cpTokenAddress, bytes memory toChainCPTokenBytes) external onlyOwner {
        require(cpTokenBetweenTwoChainMap[toChainId][cpTokenAddress].length == 0);
        // cpToken must be registered
        require(cpAndRealTokenMap[cpTokenAddress] != address(0x0));
        cpTokenBetweenTwoChainMap[toChainId][cpTokenAddress] = toChainCPTokenBytes;
    }

    function setBridgeFeeSplitRate(uint8 _liquidityFeeRate, uint8 _daoFeeRate) external onlyOwner {
        require(_liquidityFeeRate + _daoFeeRate == 100);
        liquidityFeeRate = _liquidityFeeRate;
        daoFeeRate = _daoFeeRate;
    }

    function setBridge(uint16 toChainId, bytes calldata bridgeAddress) external onlyOwner {
        // so nice
        require(bridgeLookup[toChainId].length == 0, "Bridge already set!");
        bridgeLookup[toChainId] = bridgeAddress;
    }

    function setGasAmount(uint16 toChainId, uint8 actionType, uint256 gasAmount) external onlyOwner {
        gasLookup[toChainId][actionType] = gasAmount;
    }

    //---------------------------------------------------------------------------
    // DAO asset action
    // L0 cross-bridge does not support rebase reduce token, this type of token cannot be removeLiquidity can only be withdrawn by the administrator
    function withdrawRebaseReduceToken(address tokenAddress, uint256 amount) external onlyOwner {
        uint256 balanceBefore = IERC20(tokenAddress).balanceOf(address(this));
        require(tokenPoolMap[tokenAddress] > balanceBefore);
        IERC20(address(this)).safeTransfer(msg.sender, amount);
    }

    function withdrawTeamAndDAOFee(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(msg.sender, daoBridgeFeeMap[tokenAddress]);
        daoBridgeFeeMap[tokenAddress] = 0;
    }

    //---------------------------------------------------------------------------
    // Interface Function
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyOwner {
        layerZeroEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    // generic config for user Application
    function setConfig(uint16 _version, uint16 _chainId, uint256 _configType, bytes calldata _config) external override onlyOwner {
        layerZeroEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 version) external override onlyOwner {
        layerZeroEndpoint.setSendVersion(version);
    }

    function setReceiveVersion(uint16 version) external override onlyOwner {
        layerZeroEndpoint.setReceiveVersion(version);
    }
}
