//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IPriceFeed {
    function latestAnswer() external view returns (int256);
}

contract BlueBet is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public MAX_TIME_TYPE;
    uint256 public MAX_TOKEN_TYPE;
    uint256 public MAX_AMOUNT_TYPE;

    struct UserInfo {
        address account;
        string  discordName;
        uint256 communityId;
        bool    isRegistered;
    }

    struct BetInfo {
        uint256 bettingAmount;

        uint256 cntUsers;
        mapping(uint256 => address) bettedUserAddresses;
        mapping(uint256 => uint256) bettedPrices;

        uint256 poolAmount;

        uint256 cntWinners;
        mapping(uint256 => address) winners;
        mapping(uint256 => uint256) winAmounts;
    }

    struct BetInfoBatch {
        uint256 timeType;

        uint256 period;
        uint256 periodToDeposit;

        uint256 startedTime;
        uint256 status;

        BetInfo[15][5] betInfo;
    }

    ////////////Users//////////////////////////////////////////////
    mapping(string => UserInfo) public userListByDiscordName;
    mapping(address => UserInfo) public userListByAddress;

    ////////////Token Config///////////////////////////////////////
    address public depositToken;
    mapping(address => uint256) public userBalance;

    uint256 public cntTokenType;
    mapping(uint256 => address) public tokenTypeList;
    mapping(address => address) public priceFeedList;

    uint256 public cntAmountType;

    ////////////Betting////////////////////////////////////////////
    uint256 public cntTimeType;
    mapping(uint256 => BetInfoBatch) public betInfoBatch;

    ////////////Revenue////////////////////////////////////////////
    uint256 public revenueForCommunity;
    address public teamAddress;

    uint256 public cntCommunity;
    uint256 public cntTotalUser;
    mapping(uint256 => address) public communityAddresses;
    mapping(uint256 => uint256) public userCountListForCommunity;
    mapping(uint256 => uint256) public ratingListForCommunity; // 0: 5%, 1: 7.5%

    ///////////BettingKeeper/////////////////////////////////////////////
    mapping (address => bool) public isBettingKeeper;

    event SetBettingKeeper(address indexed account, bool isActive);
    event RegisterUserInfo(string _discordName, uint256 _communityId);
    event SetTokenTypeCount(uint256 _count);
    event SetAmountTypeCount(uint256 _count);
    event SetTokenConfig(uint256 _tokenType, address _token, address _priceFeed);
    event SetDepositToken(address _depositToken);
    event SetTeamAddress(address _address);
    event SetCommunityCount(uint256 _count);
    event SetCommunityAddress(uint256 _communityId, address _address);
    event ClearUserCountForCommunity(uint256 _communityId);
    event SetCommunityRating(uint256 _communityId, uint256 _rating);
    event DepositByUser(uint256 _amount);
    event WithdrawByUser(uint256 _amount);
    event WithdrawRevenue();
    event WithdrawAll();
    event DoBet(string _discordName, uint256 _timeType, uint256 _tokenType, uint256 _price);
    event SetTimeTypeCount(uint256 _count);
    event SetBettingAmount(uint256 _timeType, uint256 _tokenType, uint256 _amountType, uint256 _bettingAmount);
    event PrepareBetting(uint256 _timeType, uint256 _period, uint256 _periodToDeposit);
    event StartBetting(uint256 _timeType);
    event EndBetting(uint256 _timeType);

    modifier onlyBettingKeeper() {
        require(isBettingKeeper[msg.sender], "403");
        _;
    }

    function initialize() public initializer {
        MAX_TIME_TYPE = 10;
        MAX_TOKEN_TYPE = 15;
        MAX_AMOUNT_TYPE = 5;

        depositToken = 0x21C30a738638330cf8573756355eE3e9d6001f31;
        teamAddress = 0xb8E2408cCCcE6F8396245e5C84F52BCC8985cE9D;

        cntTimeType = 0;
        cntTokenType = 0;
        cntAmountType = 0;

        revenueForCommunity = 0;

        cntCommunity = 3;
        communityAddresses[0] = 0x5d2E4189d0b273d7E7C289311978a0183B96C404;
        communityAddresses[1] = 0x2A567DDf64eDE5782f416A1e729504a31990f957;
        communityAddresses[2] = 0xe556a2833cd737379765dAac511E80AFBec758D2;
        ratingListForCommunity[0] = 0;
        ratingListForCommunity[1] = 0;
        ratingListForCommunity[2] = 0;

        cntTotalUser = 0;

        __Ownable_init();
    }

    function setBettingKeeper(address _account, bool _isActive) external onlyOwner() {
        isBettingKeeper[_account] = _isActive;
        emit SetBettingKeeper(_account, _isActive);
    }

    function registerUserInfo(string memory _discordName, uint256 _communityId) public {
        UserInfo memory temp = userListByAddress[msg.sender];
        if (temp.isRegistered) {
            userListByDiscordName[temp.discordName].isRegistered = false;
        }

        UserInfo memory temp1 = userListByDiscordName[_discordName];
        if (temp1.isRegistered) {
            userListByAddress[temp1.account].isRegistered = false;
        }

        UserInfo memory user;
        user.account = msg.sender;
        user.discordName = _discordName;
        user.communityId = _communityId;
        user.isRegistered = true;
        
        userListByAddress[msg.sender] = user;
        userListByDiscordName[_discordName] = user;

        emit RegisterUserInfo(_discordName, _communityId);
    }

    function setTokenTypeCount(uint256 _count) public onlyOwner() {
        require(_count <= MAX_TOKEN_TYPE, "Invalid TokenType count");

        cntTokenType = _count;

        emit SetTokenTypeCount(_count);
    }

    function setAmountTypeCount(uint256 _count) public onlyOwner() {
        require(_count <= MAX_AMOUNT_TYPE, "Invalid AmountType count");

        cntAmountType = _count;

        emit SetAmountTypeCount(_count);
    }

    function setTokenConfig(uint256 _tokenType, address _token, address _priceFeed) public onlyOwner() {
        require(cntTokenType > _tokenType, "Invalid tokenType");

        tokenTypeList[_tokenType] = _token;
        priceFeedList[_token] = _priceFeed;

        emit SetTokenConfig(_tokenType, _token, _priceFeed);
    }

    function setDepositToken(address _depositToken) public onlyOwner() {
        depositToken = _depositToken;

        emit SetDepositToken(_depositToken);
    }

    function setTeamAddress(address _address) public onlyOwner() {
        teamAddress = _address;

        emit SetTeamAddress(_address);
    }

    function setCommunityCount(uint256 _count) public onlyOwner() {
        cntCommunity = _count;

        emit SetCommunityCount(_count);
    }

    function setCommunityAddress(uint256 _communityId, address _address) public onlyOwner() {
        require(cntCommunity > _communityId, "Invalid communityId");

        communityAddresses[_communityId] = _address;

        emit SetCommunityAddress(_communityId, _address);
    }

    function clearUserCountForCommunity(uint256 _communityId) public onlyOwner() {
        userCountListForCommunity[_communityId] = 0;

        emit ClearUserCountForCommunity(_communityId);
    }

    function setCommunityRating(uint256 _communityId, uint256 _rating) public onlyOwner() {
        require(cntCommunity > _communityId, "Invalid communityId");
        require(_rating < 2, "Invalid rating");
        ratingListForCommunity[_communityId] = _rating;

        emit SetCommunityRating(_communityId, _rating);
    }

    function depositByUser(uint256 _amount) public {
        require(_amount > 0, "Bluebet: amount is zero");

        IERC20(depositToken).safeTransferFrom(msg.sender, address(this), _amount);
        userBalance[msg.sender] += _amount;

        emit DepositByUser(_amount);
    }

    function withdrawByUser(uint256 _amount) public {
        require(userBalance[msg.sender] >= _amount, "Bluebet: user has no coin in betting contract");

        IERC20(depositToken).safeTransfer(msg.sender, _amount);
        userBalance[msg.sender] -= _amount;

        emit WithdrawByUser(_amount);
    }

    function withdrawRevenue() public onlyOwner {
        require(revenueForCommunity > 0, "There is no revenue");
        
        IERC20(depositToken).safeTransfer(teamAddress, revenueForCommunity / 3 * 2);
        
        uint256 revenueForRating0 = revenueForCommunity / 3;
        uint256 revenueForRating1 = revenueForCommunity / 2;

        for (uint256 i = 0; i < cntCommunity; i ++) {
            if (ratingListForCommunity[i] == 0)
                IERC20(depositToken).safeTransfer(communityAddresses[i], revenueForRating0 / cntTotalUser * userCountListForCommunity[i]);
            else
                IERC20(depositToken).safeTransfer(communityAddresses[i], revenueForRating1 / cntTotalUser * userCountListForCommunity[i]);
            userCountListForCommunity[i] = 0;
        }
        
        revenueForCommunity = 0;
        cntTotalUser = 0;

        emit WithdrawRevenue();
    }

    function withdrawAll() public onlyOwner {
        IERC20(depositToken).safeTransfer(msg.sender, IERC20(depositToken).balanceOf(address(this)));

        emit WithdrawAll();
    }

    function getBalanceByDiscordName(string memory _discordName) public view returns (uint256) {
        return userBalance[userListByDiscordName[_discordName].account];
    }

    function getBettingAmounts(uint256 _timeType, uint256 _tokenType) public view returns (
        uint256[] memory _bettingAmounts
    ) {
        uint256[] memory bettingAmounts = new uint256[](MAX_AMOUNT_TYPE);
        for (uint256 i = 0; i < MAX_AMOUNT_TYPE; i ++)
            bettingAmounts[i] = betInfoBatch[_timeType].betInfo[_tokenType][i].bettingAmount;

        return bettingAmounts;
    }

    function getBettedUsers(uint256 _timeType, uint256 _tokenType, uint256 _amountType) public view returns (
        uint256 _cntUsers,
        string[] memory _bettedUserDiscordNames,
        address[] memory _bettedUserAddresses,
        uint256[] memory _bettedPrices
    ) {
        uint256 cntUsers = betInfoBatch[_timeType].betInfo[_tokenType][_amountType].cntUsers;

        string[] memory bettedUserDiscordNames = new string[](cntUsers);
        address[] memory bettedUserAddresses = new address[](cntUsers);
        uint256[] memory bettedPrices = new uint256[](cntUsers);
        for (uint256 i = 0; i < cntUsers; i ++) {
            bettedUserDiscordNames[i] = (userListByAddress[betInfoBatch[_timeType].betInfo[_tokenType][_amountType].bettedUserAddresses[i]].discordName);
            bettedUserAddresses[i] = (betInfoBatch[_timeType].betInfo[_tokenType][_amountType].bettedUserAddresses[i]);
            bettedPrices[i] = (betInfoBatch[_timeType].betInfo[_tokenType][_amountType].bettedPrices[i]);
        }

        return (
            cntUsers,
            bettedUserDiscordNames,
            bettedUserAddresses,
            bettedPrices
        );
    }

    function getWinners(uint256 _timeType, uint256 _tokenType, uint256 _amountType) public view returns (
        uint256 _poolAmount,
        uint256 _cntWinners,
        address[] memory _winnersAddresses,
        uint256[] memory _winAmounts
    ) {
        uint256 poolAmount = betInfoBatch[_timeType].betInfo[_tokenType][_amountType].poolAmount;

        uint256 cntWinners = betInfoBatch[_timeType].betInfo[_tokenType][_amountType].cntWinners;
        
        address[] memory winnersAddresses = new address[](cntWinners);
        uint256[] memory winAmounts = new uint256[](cntWinners);

        for (uint256 i = 0; i < cntWinners; i ++) {
            winnersAddresses[i] = (betInfoBatch[_timeType].betInfo[_tokenType][_amountType].winners[i]);
            winAmounts[i] = (betInfoBatch[_timeType].betInfo[_tokenType][_amountType].winAmounts[i]);
        }

        return (
            poolAmount,
            cntWinners,
            winnersAddresses,
            winAmounts
        );
    }

    function doBet(string memory _discordName, uint256 _timeType, uint256 _tokenType, uint256 _amountType, uint256 _price) public onlyBettingKeeper {
        require(cntTimeType >= _timeType, "Invalid time type");
        require(cntTokenType >= _tokenType, "Invalid token type");
        require(cntAmountType >= _amountType, "Invalid amount type");

        require(betInfoBatch[_timeType].status == 1, "no on-going betting");

        address userAccount = userListByDiscordName[_discordName].account;

        require(userBalance[userAccount] >= betInfoBatch[_timeType].betInfo[_tokenType][_amountType].bettingAmount, "insufficient funds for this user");

        for (uint256 i = 0; i < betInfoBatch[_timeType].betInfo[_tokenType][_amountType].cntUsers; i ++) {
            require(betInfoBatch[_timeType].betInfo[_tokenType][_amountType].bettedUserAddresses[i] != userAccount, "this user already betted");
        }
        
        betInfoBatch[_timeType].betInfo[_tokenType][_amountType].bettedUserAddresses[betInfoBatch[_timeType].betInfo[_tokenType][_amountType].cntUsers] = userAccount;
        betInfoBatch[_timeType].betInfo[_tokenType][_amountType].bettedPrices[betInfoBatch[_timeType].betInfo[_tokenType][_amountType].cntUsers] = _price;
        betInfoBatch[_timeType].betInfo[_tokenType][_amountType].cntUsers ++;

        userBalance[userAccount] -= betInfoBatch[_timeType].betInfo[_tokenType][_amountType].bettingAmount;
        betInfoBatch[_timeType].betInfo[_tokenType][_amountType].poolAmount += betInfoBatch[_timeType].betInfo[_tokenType][_amountType].bettingAmount;

        cntTotalUser ++;

        emit DoBet(_discordName, _timeType, _tokenType, _price);
    }

    function setTimeTypeCount(uint256 _count) public onlyOwner() {
        require(_count <= MAX_TIME_TYPE, "Invalid TimeType count");

        cntTimeType = _count;

        emit SetTimeTypeCount(_count);
    }

    function setBettingAmount(uint256 _timeType, uint256 _tokenType, uint256 _amountType, uint256 _bettingAmount) public onlyOwner() {
        require(cntTimeType > _timeType, "Invalid timeType");
        require(cntTokenType > _tokenType, "Invalid tokenType");
        require(cntAmountType > _amountType, "Invalid amountType");

        betInfoBatch[_timeType].betInfo[_tokenType][_amountType].bettingAmount = _bettingAmount;

        emit SetBettingAmount(_timeType, _tokenType, _amountType, _bettingAmount);
    }

    function prepareBetting(uint256 _timeType, uint256 _period, uint256 _periodToDeposit) public onlyOwner() {
        require(cntTimeType > _timeType, "Invalid timeType");

        betInfoBatch[_timeType].status = 0;

        betInfoBatch[_timeType].period = _period;
        betInfoBatch[_timeType].periodToDeposit = _periodToDeposit;

        emit PrepareBetting(_timeType, _period, _periodToDeposit);
    }

    function startBetting(uint256 _timeType) public onlyBettingKeeper() {
        require(cntTimeType > _timeType, "Invalid timeType");

        betInfoBatch[_timeType].status = 1;

        betInfoBatch[_timeType].startedTime = block.timestamp;
        for (uint256 i = 0; i < cntTokenType; i ++) {
            for (uint256 j = 0; j < cntAmountType; j ++) {
                betInfoBatch[_timeType].betInfo[i][j].poolAmount = 0;
                betInfoBatch[_timeType].betInfo[i][j].cntUsers = 0;
                betInfoBatch[_timeType].betInfo[i][j].cntWinners = 0;
            }
        }

        emit StartBetting(_timeType);
    }

    function endBetting(uint256 _timeType) public onlyBettingKeeper() {
        require(cntTimeType > _timeType, "Invalid timeType");

        betInfoBatch[_timeType].status = 2;

        for (uint256 i = 0; i < cntTokenType; i ++) {
            uint256 realPrice = (uint256)(IPriceFeed(priceFeedList[tokenTypeList[i]]).latestAnswer());

            for (uint256 j = 0; j < cntAmountType; j ++) {
                uint256 comparePrice = realPrice;
                if (betInfoBatch[_timeType].betInfo[i][j].cntUsers == 1) {
                    userBalance[betInfoBatch[_timeType].betInfo[i][j].bettedUserAddresses[0]] += betInfoBatch[_timeType].betInfo[i][j].bettingAmount;
                    betInfoBatch[_timeType].betInfo[i][j].poolAmount -= betInfoBatch[_timeType].betInfo[i][j].bettingAmount;
                    betInfoBatch[_timeType].betInfo[i][j].winners[betInfoBatch[_timeType].betInfo[i][j].cntWinners] = betInfoBatch[_timeType].betInfo[i][j].bettedUserAddresses[0];
                    betInfoBatch[_timeType].betInfo[i][j].cntWinners ++;
                    continue;
                }

                for (uint256 k = 0; k < betInfoBatch[_timeType].betInfo[i][j].cntUsers; k ++) {
                    address curAddress = betInfoBatch[_timeType].betInfo[i][j].bettedUserAddresses[k];
                    userCountListForCommunity[userListByAddress[curAddress].communityId] ++;

                    uint256 dif = (realPrice > betInfoBatch[_timeType].betInfo[i][j].bettedPrices[k]) ? (realPrice - betInfoBatch[_timeType].betInfo[i][j].bettedPrices[k]) : (betInfoBatch[_timeType].betInfo[i][j].bettedPrices[k] - realPrice);
                    if (dif == comparePrice && betInfoBatch[_timeType].betInfo[i][j].cntWinners >= 1) {
                        betInfoBatch[_timeType].betInfo[i][j].winners[betInfoBatch[_timeType].betInfo[i][j].cntWinners] = betInfoBatch[_timeType].betInfo[i][j].bettedUserAddresses[k];
                        betInfoBatch[_timeType].betInfo[i][j].cntWinners ++;
                    } else if (dif < comparePrice) {
                        comparePrice = dif;
                        betInfoBatch[_timeType].betInfo[i][j].winners[0] = betInfoBatch[_timeType].betInfo[i][j].bettedUserAddresses[k];
                        betInfoBatch[_timeType].betInfo[i][j].cntWinners = 1;
                    }
                }

                for (uint256 k = 0; k < betInfoBatch[_timeType].betInfo[i][j].cntWinners; k ++) {
                    betInfoBatch[_timeType].betInfo[i][j].winAmounts[k] = (betInfoBatch[_timeType].betInfo[i][j].poolAmount * 85 / 100) / betInfoBatch[_timeType].betInfo[i][j].cntWinners;
                    userBalance[betInfoBatch[_timeType].betInfo[i][j].winners[k]] += betInfoBatch[_timeType].betInfo[i][j].winAmounts[k];
                }

                revenueForCommunity += betInfoBatch[_timeType].betInfo[i][j].poolAmount * 15 / 100;
            }
        }

        emit EndBetting(_timeType);
    }

    receive() payable external {}
}