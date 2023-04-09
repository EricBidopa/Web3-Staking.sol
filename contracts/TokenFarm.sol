// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//I want this contract to anable;
// stakeTokens -
// unStakeTokens -
// issue new Tokens for rewarding users in correlation with the amount staked-
// addAllowedTokensonspecificblockchain -
// getValueofUnderlined staked token-

import "@openzeppelin/contracts/access/Ownable.sol";
//import ERC-20 interface (IERC20)
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

//Ownable inherits from the openZeppelin ownable libary as imported above
//This saves the stress of having to make a custom onlyOwner modifier.Simply inherited from openZeppelin
contract TokenFarm is Ownable {
    // this mapping below keeps track of how much of what token each user has staked. Tokenaddress ->user address->amount staked.
    mapping(address => mapping(address => uint256)) public stakingBalance;
    // uniqueTokensStaked Mapping to know how many different tokens each user has staked.
    mapping(address => uint256) public uniqueTokensStaked;

    //this mapping is going to map a token to their price.
    mapping(address => address) public tokenPriceFeedMapping;
    //I had to create a stakers-address array for looping since mapping cannot be looped through.
    address[] public stakers;
    //List for tokens that can be staked on the platform is below;
    address[] public allowedTokens;
    IERC20 public dappToken;

    // 100 ETH 1:1 for every 1 ETH, we give 1 dappToken
    // 50 ETH and 50 DAI staked, and we want to give a reward of 1 dapp / 1 DAI

    //Constructor below gets the address of the dappToken right on deployment of contract
    constructor(address _dappTokenAddress) public {
        dappToken = IERC20(_dappTokenAddress);
    }

    function setPriceFeedContract(
        address _token,
        address _priceFeedz
    ) public onlyOwner {
        tokenPriceFeedMapping[_token] = _priceFeed;
    }

    function issueTokens() public onlyOwner {
        // Issue token reward to all stakers
        for (
            uint256 stakersIndex = 0;
            stakersIndex < stakers.length;
            stakersIndex++
        ) {
            //transfer reward dapptoken to staker
            address recipient = stakers[stakersIndex];
            uint256 userTotalValue = getUserTotalValue(recipient);
            dappToken.transfer(recipient, userTotalValue);
        }
    }

    //function to get staker's total amount staked and calculate the amount of dappToken to be given to the staker/user.
    //this is the total value of tokens staked by a user
    function getUserTotalValue(address _user) public view returns (uint256) {
        uint256 totalValue = 0;
        require(
            uniqueTokensStaked[_user] > 0,
            " you don;t have any tokens staked!"
        );
        for (
            uint256 allowedTokensIndex = 0;
            allowedTokensIndex < allowedTokens.length;
            allowedTokensIndex++
        ) {
            //get the toal value across one token
            totalValue =
                totalValue +
                getUserSingleTokenValue(
                    _user,
                    allowedTokens[allowedTokensIndex]
                );
        }
        return totalValue;
    }

    //function gets the token value of a particular staked token.
    //gets the value of how much a staker staked of a particular token.
    //This is the conversion value.
    function getUserSingleTokenValue(
        address _user,
        address _token
    ) public view returns (uint256) {
        if (uniqueTokensStaked[_user] <= 0) {
            return 0;
        }
        (uint256 price, uint256 decimals) = getTokenValue(_token);
        return ((stakingBalance[_token][_user] * price) / (10 ** decimals));
    }

    //get value of token staked by user.
    function getTokenValue(
        address _token
    ) public view returns (uint256, uint256) {
        // priceFeedAddress
        address priceFeedAddress = tokenPriceFeedMapping[_token];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            priceFeedAddress
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 decimals = uint256(priceFeed.decimals());
        return (uint256(price), decimals);
    }

    //Stake token function-Done
    //transfers tokens from the user's wallet to the contract.
    //check if the staker has already staked and if not, the new user is added to the staker's list as declared above.
    function stakeTokens(uint256 _amount, address _token) public {
        //How much users can stake
        require(_amount > 0, "Amount must be more than 0");
        //what tokens is enabled for staking on the platform
        require(tokenIsAllowed(_token), "Stakiing this token is not allowed");

        //transferfrom function on ERC-20 since this contract doesn't own the tokens but rathr owned by openZepplin interface as imported above
        //The token created in the dappToken.sol is solely for rewards. Users rather stake allow=ed token that already exist in ERC-20 as zepplinAllows.
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        //new staker is only added if he/she is not already as a staker on the platform.
        //checks for how mnay unique tokens the users has.
        updateUniqueTokensStaked(msg.sender, _token);
        stakingBalance[_token][msg.sender] =
            stakingBalance[_token][msg.sender] +
            _amount;
        // if the user has staked at least on of the accepted tokens, they get address to the stakers list above to qualify for rewards
        if (uniqueTokensStaked[msg.sender] == 1) {
            stakers.push(msg.sender);
        }
    }

    function unstakeTokens(address _token) public {
        uint256 balance = stakingBalance[_token][msg.sender];
        require(balance > 0, "You don't have tokens to unstake");
        IERC20(_token).transfer(msg.sender, balance);
        //below records and maps the staking data into the mapping declared at the topmost of this contract.
        stakingBalance[_token][msg.sender] = 0;
        uniqueTokensStaked[msg.sender] = uniqueTokensStaked[msg.sender] - 1;
        // The code below fixes a problem not addressed in the video, where stakers could appear twice
        // in the stakers array, receiving twice the reward.
        if (uniqueTokensStaked[msg.sender] == 0) {
            for (
                uint256 stakersIndex = 0;
                stakersIndex < stakers.length;
                stakersIndex++
            ) {
                if (stakers[stakersIndex] == msg.sender) {
                    stakers[stakersIndex] = stakers[stakers.length - 1];
                    stakers.pop();
                }
            }
        }
    }

    //This function is to assist issueTokens function to reward users based on the amount they have staked. minimu amount to qualify for the reward it stake at least one *type* of the suppoted token.
    //function for only added if they are not already on the stakers list as declared above(top of contract)
    //checks for how mnay unique tokens the user has
    //This is an internal function.
    function updateUniqueTokensStaked(address _user, address _token) internal {
        if (stakingBalance[_token][_user] <= 0) {
            //mapping decared above
            uniqueTokensStaked[_user] = uniqueTokensStaked[_user] + 1;
        }
    }

    //This function enables only the owner or the address that deployed the contract to add the specific token addresses that are enabled on the platform.
    function addAllowedTokens(address _token) public onlyOwner {
        //allowedTokens is a list of allowed tokens declared at the top of this contract
        allowedTokens.push(_token);
    }

    //functions for tokens that are allowed for staking on the platform
    //returns bool (true id token is allowed or false if token is not allowed)
    function tokenIsAllowed(address _token) public view returns (bool) {
        for (
            //loops through allowed token list and check if the address matched any address in the allowed tokens list.
            uint256 allowedTokensIndex = 0;
            allowedTokensIndex < allowedTokens.length;
            allowedTokensIndex++
        ) {
            if (allowedTokens[allowedTokensIndex] == _token) {
                return true;
            }
        }
        return false;
    }
}
