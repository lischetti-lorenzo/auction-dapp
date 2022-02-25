//SPDX-License-Identifier: MIT

pragma solidity >=0.5.0 <0.9.0;

contract AuctionFactory {
  Auction[] public deployedAuctions;

  function createAuction() public {
    Auction newAuction = new Auction(msg.sender);
    deployedAuctions.push(newAuction);
  }
  
  function getDeployedAuctions() public view returns (Auction[] memory) {
    return deployedAuctions;
  }
}

contract Auction {
  address payable public owner;
  uint public startBlock;
  uint public endBlock;
  string public ipfsHash;
  enum State {Started, Running, Ended, Cancelled}
  State public auctionState;

  uint public highestBindingBid;
  address payable public highestBidder;

  mapping(address=>uint) public bids;
  uint bidIncrement;

  //the owner can finalize the auction and get the highestBindingBid only once
  bool public ownerGotFunds = false;

  constructor(address creator) {
    owner = payable(creator);
    auctionState = State.Running;
    startBlock = block.number;
    // There will be 40320 blocks generated in a week.
    // The auction will be running for a week.
    endBlock = startBlock + 40320;
    ipfsHash = "";
    bidIncrement = 100;
  }

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  modifier notOwner() {
    require(msg.sender != owner);
    _;
  }

  modifier afterStart() {
    require(block.number >= startBlock);
    _;
  }

  modifier beforeEnd() {
    require(block.number <= endBlock);
    _;
  }

  function min(uint a, uint b) pure internal returns(uint) {
    if (a <= b) {
      return a;
    } else {
      return b;
    }
  }

  function placeBid() public payable notOwner afterStart beforeEnd {
    require(auctionState == State.Running);
    require(msg.value >= 100);

    uint currentBid = bids[msg.sender] + msg.value;
    require(currentBid > highestBindingBid);
    bids[msg.sender] = currentBid;

    if (currentBid <= bids[highestBidder]) {
      highestBindingBid = min(currentBid + bidIncrement, bids[highestBidder]);
    } else {
      highestBindingBid = min(currentBid, bids[highestBidder] + bidIncrement);
      highestBidder = payable(msg.sender);
    }
  }

  function cancelAuction() public onlyOwner {
    auctionState = State.Cancelled;
  }

  function finalizeAuction() public {
    // the auction has been canceled or ended
    require(auctionState == State.Cancelled || block.number > endBlock);

    // only the owner or a bidder can finalize the auction
    require(msg.sender == owner || bids[msg.sender] > 0);

    address payable recipient;
    uint value;

    if (auctionState == State.Cancelled) {
      recipient = payable(msg.sender);
      value = bids[msg.sender];
    } else {
      // auction ended
      // the owner finalizes de auction
      if (msg.sender == owner && !ownerGotFunds) {
        recipient = payable(msg.sender);
        value = highestBindingBid;

        //the owner can finalize the auction and get the highestBindingBid only once
        ownerGotFunds = true; 
      } else {
        // another user different from the owner finalizes the auction
        if (msg.sender == highestBidder) {
          // the highestBidder finalizes the auction
          recipient = highestBidder;
          value = bids[highestBidder] - highestBindingBid;
        } else {
          // neither the owner or the highestBidder finalizes the auction
          recipient = payable(msg.sender);
          value = bids[msg.sender];
        }
      }
    }

    // resetting the bid of the recipient to 0
    bids[recipient] = 0;

    recipient.transfer(value);
  }
}