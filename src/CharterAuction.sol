// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CharterAuction
/// @notice An auction contract with blind rounds where a position owner receives a reward each time their position is selected in a new round.
contract CharterAuction {
    using SafeERC20 for IERC20;

    IERC20 public usdt;
    uint256 public entryFee; // The fixed fee required to buy a position.
    uint256 public currentRound;
    uint256 public minRaisedFunds;
    uint256 public totalRaisedFunds;
    uint256 public constant MIN_POSITIONS = 3;
    address public broker;
    address public winner;

    // Mapping to store reward balances for each bidder.
    mapping(address => uint256) public rewards;

    struct Position {
        address[] rewarders;
        uint256 bidPrice; // The revealed bid price (position price).
    }

    struct BidderInfo {
        address bidder;
        uint256[] bidPrices;
    }

    struct Round {
        Position[] positions;
        BidderInfo[] bidders;
        bool ended;
    }

    mapping(uint256 => Round) public rounds;

    event AuctionCreated(address indexed broker, uint256 indexed round, address indexed usdt, uint256 entryFee, uint256 minRaisedFunds);
    event BidEntered(uint256 indexed round, address indexed bidder, uint256 bidPrice);
    event NewRoundStarted(uint256 indexed round);
    event EndAuction(uint256 indexed round, uint256 targetPrice, address winner);
    event RewardWithdrawn(address indexed rewarder, uint256 amount);
    event BidPosition(uint256 indexed round, uint256 positionIndex, address indexed bidder, uint256 entryFee);

    error InvalidUSDTAddress();
    error InvalidBidPrice();
    error InvalidEntryFee();
    error TransferFailed();
    error InsufficientBalance();
    error RoundEnded();
    error InvalidMinRaisedFunds();
    error DoubleBid();
    error RoundAlreadyEnded();
    error StillInBlindRound();
    error CannotEndBlindRound();
    error NoRewards();
    error InvalidPositionIndex();

    /// @notice Initialize the auction with the USDT token address and entry fee.
    constructor(address _usdt, uint256 _entryFee, uint256 _minRaisedFunds, address _broker) {
        if (_usdt == address(0)) revert InvalidUSDTAddress();
        if (_entryFee == 0) revert InvalidEntryFee();
        if (_minRaisedFunds == 0) revert InvalidMinRaisedFunds();

        usdt = IERC20(_usdt);
        broker = _broker;
        entryFee = _entryFee;
        minRaisedFunds = _minRaisedFunds;

        currentRound = 0;

        emit AuctionCreated(broker, currentRound, _usdt, _entryFee, _minRaisedFunds);
    }

    /// @notice Enter the current round by paying the entry fee.
    function bidAtBlindRound(uint256 _bidPrice) external {
        if (rounds[currentRound].ended) revert RoundEnded();
        if(usdt.balanceOf(msg.sender) < entryFee) revert InsufficientBalance();
        usdt.safeTransferFrom(msg.sender, address(this), entryFee);  // SafeERC20 will revert on failure
        if (checkDoubleBid(_bidPrice, msg.sender)) revert DoubleBid();

        if (totalRaisedFunds + entryFee > minRaisedFunds) {
          turnToNextRound();
          return;
        }

        uint256 bidderIndex = searchBidder(msg.sender);
        if (bidderIndex < rounds[currentRound].bidders.length) {
            rounds[currentRound].bidders[bidderIndex].bidPrices.push(_bidPrice);
        } else {
            uint256[] memory initialBidPrices = new uint256[](1);
            initialBidPrices[0] = _bidPrice;
            rounds[currentRound].bidders.push(BidderInfo({
                bidder: msg.sender,
                bidPrices: initialBidPrices
            }));
        }

        emit BidEntered(currentRound, msg.sender, _bidPrice);
    }

    function checkDoubleBid(uint256 _bidPrice, address _bidder) internal view returns (bool) {
      uint256 bidderIndex = searchBidder(_bidder);
      if (bidderIndex < rounds[currentRound].bidders.length) {
        for (uint256 i = 0; i < rounds[currentRound].bidders[bidderIndex].bidPrices.length; i++) {
          if (rounds[currentRound].bidders[bidderIndex].bidPrices[i] == _bidPrice) {
            return true;
          }
        }
      }
      return false;
    }

    function searchPosition(uint256 _bidPrice) internal view returns (uint256) {
      uint256 i = 0;
      for (i = 0; i < rounds[currentRound].positions.length; i++) {
        if (rounds[currentRound].positions[i].bidPrice == _bidPrice) {
          break;
        }
      }
      return i;
    }

    function searchBidder(address _bidder) internal view returns (uint256) {
      uint256 i = 0;
      for (i = 0; i < rounds[currentRound].bidders.length; i++) {
        if (rounds[currentRound].bidders[i].bidder == _bidder) {
          break;
        }
      }
      return i;
    }

    function turnToNextRound() public {
      if (rounds[currentRound].ended) revert RoundAlreadyEnded();
      uint256 sumBidPrices = 0;

      if(currentRound == 0) {
        if(msg.sender != broker && msg.sender != address(this)) revert CannotEndBlindRound();
      }

      rounds[currentRound].ended = true;

      for (uint256 i = 0; i < rounds[currentRound].bidders.length; i++) {
        sumBidPrices = 0;
        for (uint256 j = 0; j < rounds[currentRound].bidders[i].bidPrices.length; j++) {
          sumBidPrices += rounds[currentRound].bidders[i].bidPrices[j];
        }
        uint256 newPrice = sumBidPrices / rounds[currentRound].bidders.length;

        uint256 positionIndex = searchPosition(newPrice);
        if (positionIndex < rounds[currentRound].positions.length) {
            rounds[currentRound].positions[positionIndex].rewarders.push(rounds[currentRound].bidders[i].bidder); 
        } else {
            Position storage newPosition = rounds[currentRound].positions.push();
            newPosition.bidPrice = newPrice;
            newPosition.rewarders.push(rounds[currentRound].bidders[i].bidder);
        }
      }

      currentRound++;

      if(rounds[currentRound].positions.length < MIN_POSITIONS) {
        uint256 targetPrice;
        uint256 minDeltaPrice = type(uint256).max; // Initialize to max value
        uint256 minDeltaPriceIndex;
        uint256 deltaPrice;
        
        targetPrice = getTargetPrice();

        for (uint256 i = 0; i < rounds[currentRound].positions.length; i++) {
            if (rounds[currentRound].positions[i].bidPrice >= targetPrice) {
                deltaPrice = rounds[currentRound].positions[i].bidPrice - targetPrice;
            } else {
                deltaPrice = targetPrice - rounds[currentRound].positions[i].bidPrice;
            }
            if (deltaPrice < minDeltaPrice) {
                minDeltaPrice = deltaPrice;
                minDeltaPriceIndex = i;
            }
        }

        winner = rounds[currentRound].positions[minDeltaPriceIndex].rewarders[0];

        emit EndAuction(currentRound, rounds[currentRound].positions[minDeltaPriceIndex].bidPrice, winner);
      }
      emit NewRoundStarted(currentRound);
    }

    function getTargetPrice() internal view returns (uint256) {
      uint256 sumTop3BidPrices = 0;
      uint256[] memory prices = new uint256[](rounds[currentRound].positions.length);
      for (uint256 i = 0; i < rounds[currentRound].positions.length; i++) {
        prices[i] = rounds[currentRound].positions[i].bidPrice;
      }
      prices = sortPrices(prices);
      for (uint256 i = 0; i < MIN_POSITIONS; i++) {
        sumTop3BidPrices += prices[i];
      }
      return sumTop3BidPrices / MIN_POSITIONS;
    }

    function sortPrices(uint256[] memory _prices) internal pure returns (uint256[] memory) {
      for (uint256 i = 0; i < MIN_POSITIONS; i++) {
        for (uint256 j = i + 1; j < _prices.length; j++) {
          if (_prices[i] < _prices[j]) {
            uint256 temp = _prices[i];
            _prices[i] = _prices[j];
            _prices[j] = temp;
          }
        }
      }
      return _prices;
    }
    
    /// @notice In a new round, bidders can select a position from a previous round.
    /// Each time a position is selected, the owner of that position earns a reward equal to the entry fee.
    function bidPosition(uint256 positionIndex) external {
      uint256 _bidPrice = rounds[currentRound].positions[positionIndex].bidPrice;

      if (rounds[currentRound].ended) revert RoundEnded();
      if (currentRound == 0) revert StillInBlindRound();
      if(usdt.balanceOf(msg.sender) < entryFee) revert InsufficientBalance();
      usdt.safeTransferFrom(msg.sender, address(this), entryFee);  // SafeERC20 will revert on failure
      if (checkDoubleBid(_bidPrice, msg.sender)) revert DoubleBid();
      if (positionIndex >= rounds[currentRound].positions.length) revert InvalidPositionIndex();

      address[] memory rewarders = rounds[currentRound].positions[positionIndex].rewarders;
      uint256 rewardAmount = entryFee / rewarders.length;
      for (uint256 i = 0; i < rewarders.length; i++) {
        rewards[rewarders[i]] += rewardAmount;
      }

      uint256 bidderIndex = searchBidder(msg.sender);
      if (bidderIndex < rounds[currentRound].bidders.length) {
          rounds[currentRound].bidders[bidderIndex].bidPrices.push(_bidPrice);
      } else {
        uint256[] memory initialBidPrices = new uint256[](1);
        initialBidPrices[0] = _bidPrice;
        rounds[currentRound].bidders.push(BidderInfo({
          bidder: msg.sender,
          bidPrices: initialBidPrices
        }));
      }

      emit BidPosition(currentRound, positionIndex, msg.sender, entryFee);
    }

    /// @notice Allows users to withdraw their accumulated rewards.
    function withdrawRewards() external {
        uint256 rewardAmount = rewards[msg.sender];
        if (rewardAmount == 0) revert NoRewards();
        rewards[msg.sender] = 0;
        usdt.safeTransfer(msg.sender, rewardAmount);  // SafeERC20 will revert on failure

        emit RewardWithdrawn(msg.sender, rewardAmount);
    }
}