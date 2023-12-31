// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./libs/LibString.sol";
import "./libs/LibAddress.sol";
import "./libs/LibUint.sol";
import "./IRariMine.sol";
import "./ILocking.sol";

contract RariMineV3 is OwnableUpgradeable, IRariMine {
    using LibString for string;
    using LibUint for uint256;
    using LibAddress for address;

    IERC20Upgradeable public token;
    address public tokenOwner;
    ILocking public locking;

    uint256 public claimFormulaClaim;
    uint256 public claimCliffWeeks;
    uint256 public claimSlopeWeeks;
    uint256 constant CLAIM_FORMULA_DIVIDER = 10000;

    uint8 public constant VERSION = 1;

    mapping(address => uint256) public claimed;

    address public signer;

    event SetClaimFormulaClaim(uint256 indexed newClaimFormulaClaim);
    event SetClaimCliffWeeks(uint256 indexed newClaimCliffWeeks);
    event SetClaimSlopeWeeks(uint256 indexed newClaimSlopeWeeks);
    event SetNewTokenOwner(address indexed newTokenOwner);
    event SetNewLocking(address indexed newLocking);
    event SetNewSigner(address indexed newSigner);

    function __RariMineV3_init(
        IERC20Upgradeable _token,
        address _tokenOwner,
        ILocking _locking,
        uint256 _claimCliffWeeks,
        uint256 _claimSlopeWeeks,
        uint256 _claimFormulaClaim
    ) external initializer {
        __RariMineV3_init_unchained(_token, _tokenOwner, _locking, _claimCliffWeeks, _claimSlopeWeeks, _claimFormulaClaim);
        __Ownable_init_unchained();
        __Context_init_unchained();
    }

    function __RariMineV3_init_unchained(
        IERC20Upgradeable _token,
        address _tokenOwner,
        ILocking _locking,
        uint256 _claimCliffWeeks,
        uint256 _claimSlopeWeeks,
        uint256 _claimFormulaClaim
    ) internal onlyInitializing {
        token = _token;
        tokenOwner = _tokenOwner;
        locking = _locking;
        claimCliffWeeks = _claimCliffWeeks;
        claimSlopeWeeks = _claimSlopeWeeks;
        claimFormulaClaim = _claimFormulaClaim;
        signer = _msgSender();
    }

    function claim(
        Balance memory _balance,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _claimAndDelegate(_balance, _balance.recipient, v, r, s);
    }

    function claimAndDelegate(
        Balance memory _balance,
        address delegate,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _claimAndDelegate(_balance, delegate, v, r, s);
    }

    function _claimAndDelegate(
        Balance memory _balance,
        address delegate,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        require(prepareMessage(_balance, address(this)).recover(v, r, s) == signer, "signer should sign balances");

        address recipient = _balance.recipient;
        if (_msgSender() == recipient) {
            uint256 toClaim = _balance.value - claimed[recipient];
            require(toClaim > 0, "nothing to claim");
            claimed[recipient] = _balance.value;

            // claim rari tokens
            uint256 claimAmount = (toClaim * claimFormulaClaim) / (CLAIM_FORMULA_DIVIDER);
            if (claimAmount > 0) {
                require(token.transferFrom(tokenOwner, recipient, claimAmount), "transfer to msg sender is not successful");
                emit Claim(recipient, claimAmount);
                emit Value(recipient, _balance.value);
            }

            // lock some tokens
            uint256 lockAmount = toClaim - (claimAmount);
            if (lockAmount > 0) {
                require(token.transferFrom(tokenOwner, address(this), lockAmount), "transfer to RariMine is not successful");
                require(token.approve(address(locking), lockAmount), "approve is not successful");
                locking.lock(recipient, delegate, uint96(lockAmount), uint32(claimSlopeWeeks), uint32(claimCliffWeeks));
            }

            return;
        }

        revert("_msgSender() is not the receipient");
    }

    function doOverride(Balance[] memory _balances) public onlyOwner {
        for (uint256 i = 0; i < _balances.length; ++i) {
            claimed[_balances[i].recipient] = _balances[i].value;
            emit Value(_balances[i].recipient, _balances[i].value);
        }
    }

    function prepareMessage(Balance memory _balance, address _address) internal view returns (string memory) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return toString(keccak256(abi.encode(_balance, _address, VERSION, id)));
    }

    function toString(bytes32 value) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; ++i) {
            str[i * 2] = alphabet[uint8(value[i] >> 4)];
            str[1 + i * 2] = alphabet[uint8(value[i] & 0x0f)];
        }
        return string(str);
    }

    function setTokenOwner(address newTokenOwner) external onlyOwner {
        tokenOwner = newTokenOwner;
        emit SetNewTokenOwner(newTokenOwner);
    }

    function setClaimFormulaClaim(uint256 newClaimFormulaClaim) external onlyOwner {
        claimFormulaClaim = newClaimFormulaClaim;
        emit SetClaimCliffWeeks(newClaimFormulaClaim);
    }

    function setClaimCliffWeeks(uint256 newClaimCliffWeeks) external onlyOwner {
        claimCliffWeeks = newClaimCliffWeeks;
        emit SetClaimCliffWeeks(newClaimCliffWeeks);
    }

    function setClaimSlopeWeeks(uint256 newClaimSlopeWeeks) external onlyOwner {
        claimSlopeWeeks = newClaimSlopeWeeks;
        emit SetClaimCliffWeeks(newClaimSlopeWeeks);
    }

    function setLocking(address newLocking) external onlyOwner {
        locking = ILocking(newLocking);
        emit SetNewLocking(newLocking);
    }

    function setSigner(address newSigner) external onlyOwner {
        signer = newSigner;
        emit SetNewSigner(newSigner);
    }

    uint256[47] private __gap;
}
