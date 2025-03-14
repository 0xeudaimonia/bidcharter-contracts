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

    event AuctionCreated(uint256 indexed round, address indexed usdt, uint256 entryFee, uint256 minRaisedFunds);
    event BidEntered(uint256 indexed round, address indexed bidder, uint256 bidPrice);
    event NewRoundStarted(uint256 indexed round);

    error InvalidUSDTAddress();
    error InvalidBidPrice();
    error InvalidEntryFee();
    error TransferFailed();
    error InsufficientBalance();
    error RoundEnded();
    error InvalidMinRaisedFunds();
    error DoubleBid();

    /// @notice Initialize the auction with the USDT token address and entry fee.
    constructor(address _usdt, uint256 _entryFee, uint256 _minRaisedFunds) {
        if (_usdt == address(0)) revert InvalidUSDTAddress();
        if (_entryFee == 0) revert InvalidEntryFee();
        if (_minRaisedFunds == 0) revert InvalidMinRaisedFunds();

        usdt = IERC20(_usdt);

        entryFee = _entryFee;
        minRaisedFunds = _minRaisedFunds;

        currentRound = 0;

        emit AuctionCreated(currentRound, _usdt, _entryFee, _minRaisedFunds);
    }

    /// @notice Enter the current round by paying the entry fee.
    function enterBlindRound(uint256 _bidPrice) external {
        if (rounds[currentRound].ended) revert RoundEnded();
        if(usdt.balanceOf(msg.sender) < entryFee) revert InsufficientBalance();
        if (!usdt.safeTransferFrom(msg.sender, address(this), entryFee)) revert TransferFailed();
        if (checkDoubleBid(_bidPrice, msg.sender)) revert DoubleBid();

        if (totalRaisedFunds + entryFee > minRaisedFunds) {
          turnToNextRound();
          return;
        }

        uint256 bidderIndex = searchBidder(msg.sender);
        if (bidderIndex < rounds[currentRound].bidders.length) {
            rounds[currentRound].bidders[bidderIndex].bidPrices.push(_bidPrice);
        } else {
          rounds[currentRound].bidders.push(BidderInfo({
            bidder: msg.sender,
            bidPrices: [_bidPrice]
          }));
        }

        emit BidEntered(currentRound, msg.sender, _bidPrice);
    }

    function checkDoubleBid(uint256 _bidPrice, address _bidder) internal view returns (bool) {
      uint256 bidderIndex = searchBidder(_bidder);
      if (bidderIndex < rounds[currentRound].bidders.length) {
        return rounds[currentRound].bidders[bidderIndex].bidPrices.includes(_bidPrice);
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

    function turnToNextRound() internal {
      uint256 sumBidPrices = 0;
      for (uint256 i = 0; i < rounds[currentRound].bidders.length; i++) {
        sumBidPrices = 0;
        for (uint256 j = 0; j < rounds[currentRound].bidders[i].bidPrices.length; j++) {
          sumBidPrices += rounds[currentRound].bidders[i].bidPrices[j];
        }
        uint256 targetPrice = sumBidPrices / rounds[currentRound].bidders.length;

        uint256 positionIndex = searchPosition(targetPrice);
        if (positionIndex < rounds[currentRound].positions.length) {
            rounds[currentRound].positions[positionIndex].rewarders.push(rounds[currentRound].bidders[i].bidder); 
        } else {
          rounds[currentRound].positions.push(Position({
            rewarders: [rounds[currentRound].bidders[i].bidder],
            bidPrice: targetPrice,
          }));
        }
      }
      currentRound++;
      emit NewRoundStarted(currentRound);
    }

    /// @notice Reveal your bid (position price) for your entry.
    function revealBid(uint256 positionIndex, uint256 bidPrice) external {
        Round storage round = rounds[currentRound];
        require(positionIndex < round.positions.length, "Invalid position index");
        Position storage pos = round.positions[positionIndex];
        require(pos.bidder == msg.sender, "Not your position");
        require(!pos.revealed, "Already revealed");

        pos.bidPrice = bidPrice;
        pos.revealed = true;
        emit BidRevealed(currentRound, msg.sender, bidPrice);
    }

    /// @notice Ends the current round and computes a target value.
    /// For simplicity, here the target value is the average of the top 3 bids.
    function endRound() external {
        Round storage round = rounds[currentRound];
        require(!round.ended, "Round already ended");
        require(round.positions.length >= MIN_POSITIONS, "Not enough positions");

        // Ensure all bids have been revealed.
        for (uint256 i = 0; i < round.positions.length; i++) {
            require(round.positions[i].revealed, "Not all bids revealed");
        }

        // Sort positions in descending order by bidPrice (naïve bubble sort for demonstration).
        uint256 n = round.positions.length;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = i + 1; j < n; j++) {
                if (round.positions[j].bidPrice > round.positions[i].bidPrice) {
                    Position memory temp = round.positions[i];
                    round.positions[i] = round.positions[j];
                    round.positions[j] = temp;
                }
            }
        }

        uint256 count = n < 3 ? n : 3;
        uint256 targetValue;
        for (uint256 i = 0; i < count; i++) {
            targetValue += round.positions[i].bidPrice;
        }
        if (count > 0) {
            targetValue = targetValue / count;
        }

        round.ended = true;

        // Count positions that qualify for selection in the next round.
        uint256 qualifyingPositions;
        for (uint256 i = 0; i < n; i++) {
            if (round.positions[i].bidPrice < targetValue) {
                qualifyingPositions++;
            }
        }

        emit RoundEnded(currentRound, targetValue, qualifyingPositions);

        // Start a new round if conditions are met.
        if (qualifyingPositions >= MIN_POSITIONS) {
            currentRound++;
            rounds[currentRound].roundNumber = currentRound;
            emit NewRoundStarted(currentRound);
        }
    }

    /// @notice In a new round, bidders can select a position from a previous round.
    /// Each time a position is selected, the owner of that position earns a reward equal to the entry fee.
    function selectPosition(uint256 prevRound, uint256 positionIndex) external {
        require(prevRound < currentRound, "Can only select from previous rounds");
        Round storage oldRound = rounds[prevRound];
        require(oldRound.ended, "Previous round not ended");
        require(positionIndex < oldRound.positions.length, "Invalid position index");

        Position storage pos = oldRound.positions[positionIndex];
        address positionOwner = pos.bidder;

        // Increase the reward for the position owner by the entry fee.
        rewards[positionOwner] += entryFee;
        emit PositionSelected(prevRound, positionIndex, msg.sender, positionOwner, entryFee);
    }

    /// @notice Allows users to withdraw their accumulated rewards.
    function withdrawRewards() external {
        uint256 rewardAmount = rewards[msg.sender];
        require(rewardAmount > 0, "No rewards available");
        rewards[msg.sender] = 0;
        require(usdt.transfer(msg.sender, rewardAmount), "USDT transfer failed");
    }
}
