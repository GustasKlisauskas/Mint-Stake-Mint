// SPDX-License-Identifier: GPL-3.0
pragma solidity ^ 0.8 .4;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

/// @notice creates an interface for SafeTransfer function. Used to transfer NFTs.
interface Interface {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

contract Staker is IERC721Receiver {

    /// @notice original NFT contract
    address public parentNFT;
    address public owner;

    /// @notice used to set stakedRomm[] on stake()
    uint LastStruct;

    /// @notice staking time in seconds. How much seconds should it pass for every reward
    uint public StakingTime;
    /// @notice rewards. How many tokens should one get for every StakingTime loop
    uint public Multiplyer;

    /// @notice struct used for storing staking information for every new stake
    struct Stake {
        uint ID;
        uint stakingStart;
        uint stakingEnding;
        address owner;
        bool staked;
    }

    Stake[] public StakedStruct;

    /// @notice used to find NFTs position in Stake struct
    mapping(uint=> uint) public stakedRoom;
    /// @notice used by other contract to subtract tokens after they are used
    mapping(address=> uint) public subtractedTokens;
    /// @notice shows all staked tokens
    mapping(address=> uint[]) public ownerOfTokens;
    /// @notice after NFT is unstaked, function calculates all alocated tokens and adds it here
    mapping(address=> uint) public unstakedTokenEarnings;
    /// @notice used for whitelisting another contract that could use and subtract staked tokens from this contract
    mapping(address=> bool) public whitelisted;

    constructor (address _parentAddress, uint _stakingTime, uint _multiplyer) {
        parentNFT=_parentAddress;
        StakingTime=_stakingTime;
        owner=msg.sender;
        Multiplyer=_multiplyer;
    }

    modifier isOwner() {
        require(msg.sender==owner || whitelisted[msg.sender]);
        _;
    }

    /// @notice stakes selected NFT from parentNFT contract
    /// @dev sends NFT to this contract, creates struct where contract starts counting staked time
    function stake(uint[] memory _id) public {
        for(uint i; i < _id.length; i++) {
            uint _tempID=_id[i];
            Interface(parentNFT).safeTransferFrom(msg.sender, address(this), _tempID);
            Stake memory newStake=Stake(_tempID, block.timestamp, 0, msg.sender, true);
            StakedStruct.push(newStake);
            stakedRoom[_tempID]=LastStruct;
            ownerOfTokens[msg.sender].push(_tempID);
            LastStruct++;
        }
    }

    /// @notice selected NFT is transfered back to owner. Timer stops
    /// @dev sends back nft, closes struct with bool and counts staked time
    function unstake(uint[] memory _id) public {
        for(uint i; i < _id.length; i++) {
            uint _tempID=_id[i];
            uint _tempRoom=stakedRoom[_tempID];
            uint _timeDifference=block.timestamp - StakedStruct[_tempRoom].stakingStart;
            // adds unstake time to calculate time diference between stake and unstake
            StakedStruct[_tempRoom].stakingEnding=block.timestamp;
            // closes struct so that it is not counted in calculations
            StakedStruct[_tempRoom].staked=false;

            // if time difference is greater than set, calculates tokens and sends them to seperate location
            if(_timeDifference > StakingTime) {
                unstakedTokenEarnings[msg.sender]=unstakedTokenEarnings[msg.sender]+(_timeDifference / StakingTime * Multiplyer);
            }

            // transfers back the NFT
            Interface(parentNFT).safeTransferFrom(address(this), msg.sender, _tempID);
        }
    }

    /// @notice calculates tokens
    /// @dev calculates tokens in a view function to save on gas.
    function viewTokens(address _address) public view returns(uint) {
        uint _tempTokens;

        // finds all structs associated with address and calculates earned tokens. Adds them to _tempTokens
        for(uint i; i < ownerOfTokens[_address].length; i++) {
            uint _tempRoom=stakedRoom[ownerOfTokens[_address][i]];

            // if struct was unstaked, it is not counted because tokens were calculated and added to mapping in unstake function
            if(block.timestamp - StakedStruct[_tempRoom].stakingStart > StakingTime && StakedStruct[_tempRoom].staked) {
                _tempTokens=_tempTokens+(((block.timestamp - StakedStruct[_tempRoom].stakingStart) / StakingTime) * Multiplyer);
            }
        }

        // unstaked NFT tokens added to staked NFT tokens and if used by other contract, subtracted
        return(unstakedTokenEarnings[msg.sender] + _tempTokens - subtractedTokens[_address]);
    }

    /// @notice functions to return 3 numbers (staked tokens, unstaked tokens, subtracted tokens) seperately
    /// @dev these functions are used by another contract to calculate all tokens.
    // viewTokens() couldn't be used in returning all calculated tokens to other contract, so these functions are a replacement for it
    function viewAllocatedTokens(address _address) public view returns(uint) {
        return unstakedTokenEarnings[_address];
    }
    function viewsubtractedTokens(address _address) public view returns(uint) {
        return subtractedTokens[_address];
    }
    function viewActiveTokens(address _address) public view returns(uint) {
        uint _tempTokens;

        // finds all structs associated with address and calculates earned tokens. Adds them to _tempTokens
        for(uint i; i < ownerOfTokens[_address].length; i++) {
            uint _tempRoom=stakedRoom[ownerOfTokens[_address][i]];

            // if struct was unstaked, it is not counted because tokens were calculated and added to mapping in unstake function
            if(block.timestamp - StakedStruct[_tempRoom].stakingStart > StakingTime && StakedStruct[_tempRoom].staked) {
            _tempTokens = _tempTokens + (((block.timestamp - StakedStruct[_tempRoom].stakingStart) / StakingTime) * Multiplyer);
            }
    }
    return _tempTokens;
    }

    /// @notice used to subtract tokens after they are used somewhere
    /// @dev tokens should be subtracted only by trusted contract that is whitelisted
    function subtractTokens(address _address, uint _tokens) external isOwner {
        subtractedTokens[_address]=subtractedTokens[_address]+_tokens;
    }

    function transferOwnership(address _address) public isOwner {
        owner=_address;
    }

    /// @notice whitelists contract that should be able to use those tokens
    /// @dev this is a mapping, so that token use wouldn't be limited to one contract use
    function setWhitelist(address _address, bool _bool) public isOwner {
        whitelisted[_address]=_bool;
    }

    /// @notice OpenZeppelin requires ERC721Received implementation. It will not let contract receive tokens without this implementation.
    /// @dev this will give warnings on the compiler, because of unused parameters, but ERC721 standards require this function to accept all these parameters. Ignore these warnings.
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) public override returns(bytes4) {
        return this.onERC721Received.selector;
    }


}
