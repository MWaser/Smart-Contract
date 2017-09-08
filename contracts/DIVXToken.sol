pragma solidity ^0.4.11;
import "./StandardToken.sol";
import "./SafeMath.sol";

contract DIVXToken is StandardToken, SafeMath {

    // metadata
    string public constant name = "Divi Exchange Token";
    string public constant symbol = "DIVX";
    uint256 public constant decimals = 18;
    string public version = "1.0";

    // owner address
    address public fundDeposit;      // deposit address for ETH and DIVX for the project

    // crowdsale parameters
    bool public isPaused;
    uint256 public fundingStartBlock;
    uint256 public firstXRChangeBlock;
    uint256 public secondXRChangeBlock;
    uint256 public thirdXRChangeBlock;
    uint256 public fundingEndBlock;

    // Since we have different exchange rates at different stages, we need to keep track
    // of how much ether (in units of Wei) each contributed in case that we need to issue
    // a refund
    mapping (address => uint256) private weiBalances;

    // We need to keep track of how much ether has been contributed
    uint256 public totalReceivedWei;

    uint256 public constant privateExchangeRate  = 1000; // 1000 DIVX tokens per 1 ETH
    uint256 public constant firstExchangeRate    =  650; //  650 DIVX tokens per 1 ETH
    uint256 public constant secondExchangeRate   =  575; //  575 DIVX tokens per 1 ETH
    uint256 public constant thirdExchangeRate    =  500; //  500 DIVX tokens per 1 ETH

    uint256 public constant receivedWeiCap =  100 * (10**3) * 10**decimals;
    uint256 public constant receivedWeiMin =    5 * (10**3) * 10**decimals;

    // events
    event CreateDIVX(address indexed _to, uint256 _value);
    event LogRefund(address indexed _to, uint256 _value);
    event LogRedeem(address indexed _to, uint256 _value, bytes32 _DIVIAddress);

    // modifiers
    modifier onlyOwner() {
      require(msg.sender == fundDeposit);
      _;
    }

    modifier isNotPaused() {
      require(isPaused == false);
      _;
    }

    // constructor
    function DIVXToken(
        address _fundDeposit,
        uint256 _fundingStartBlock,
        uint256 _firstXRChangeBlock,
        uint256 _secondXRChangeBlock,
        uint256 _thirdXRChangeBlock,
        uint256 _fundingEndBlock) {

      isPaused = false;

      totalSupply = 0;
      totalReceivedWei = 0;

      fundDeposit = _fundDeposit;

      fundingStartBlock   = _fundingStartBlock;
      firstXRChangeBlock  = _firstXRChangeBlock;
      secondXRChangeBlock = _secondXRChangeBlock;
      thirdXRChangeBlock  = _thirdXRChangeBlock;
      fundingEndBlock     = _fundingEndBlock;
    }

    // overriden methods

    // Overridden method to check that the minimum was reached (i.e. no refund possible)
    function transfer(address _to, uint256 _value) returns (bool success) {
      require(totalReceivedWei >= receivedWeiMin);
      return super.transfer(_to, _value);
    }

    // Overridden method to check that the minimum was reached (i.e. no refund possible)
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
      require(totalReceivedWei >= receivedWeiMin);
      return super.transferFrom(_from, _to, _value);
    }

    /// @dev Accepts ether and creates new DIVX tokens.
    function createTokens() payable external isNotPaused {
      require(block.number >= fundingStartBlock);
      require(block.number <= fundingEndBlock);
      require(msg.value > 0);

      // Check the ETH cap
      uint256 checkedReceivedWei = safeAdd(totalReceivedWei, msg.value);
      require(checkedReceivedWei <= receivedWeiCap);

      // Calculate how many tokens (in units of Wei) should be awarded
      // to the contributor
      uint256 tokens = safeMult(msg.value, getCurrentTokenPrice());

      // Calculate how many tokens (in units of Wei) should be awarded to the project (20%)
      uint256 projectTokens = safeDiv(tokens, 5);

      // Increment the total received ETH and update this
      // contributor's ETH balance
      totalReceivedWei = checkedReceivedWei;
      weiBalances[msg.sender] += msg.value;

      // Increment the total supply of tokens and then deposit the tokens
      // to the contributor
      totalSupply = safeAdd(totalSupply, tokens);
      balances[msg.sender] += tokens;

      // Increment the total supply of tokens and then deposit the tokens
      // to the project
      totalSupply = safeAdd(totalSupply, projectTokens);
      balances[fundDeposit] += projectTokens;

      CreateDIVX(msg.sender, tokens);  // logs token creation
    }

    /// @dev Allows to transfer ether from the contract
    function withdrawWei(uint256 _value) external onlyOwner isNotPaused {
      require(_value <= this.balance);

      // send the eth to the project multisig wallet
      fundDeposit.transfer(_value);
    }

    /// @dev Pauses the contract
    function pause() external onlyOwner isNotPaused {
      // Move the contract to Paused state
      isPaused = true;
    }

    /// @dev Proceeds with the contract
    function unpause() external onlyOwner {
      // Move the contract to the previous state
      isPaused = false;
    }

    /// @dev Allows contributors to recover their ether in the case of a failed funding campaign.
    function refund() external {
      // prevents refund until sale period is over
      require(block.number > fundingEndBlock);
      // Refunds are only available if the minimum was not reached
      require(totalReceivedWei < receivedWeiMin);

      // Retrieve how much DIVX (in units of Wei) this account has
       uint256 divxVal = balances[msg.sender];
       require(divxVal > 0);

      // Retrieve how much ETH (in units of Wei) this account contributed
      uint256 weiVal = weiBalances[msg.sender];
      require(weiVal > 0);

      // Destroy this contributor's tokens and reduce the total supply
      balances[msg.sender] = 0;
      totalSupply = safeSubtract(totalSupply, divxVal);

      // Log this refund operation
      LogRefund(msg.sender, weiVal);

      // Send the money back
      msg.sender.transfer(weiVal);
    }

    /// @dev Redeems tokens and records the address of the sender in the new blockchain
    function redeem(bytes32 DiviAddress) external {
      uint256 divxVal = balances[msg.sender];

      // Move the tokens of the caller to the project's address
      assert(super.transfer(fundDeposit, divxVal));

      // Log the redeeming of this tokens
      LogRedeem(msg.sender, divxVal, DiviAddress);
    }


    /// @dev Returns the current token price
    function getCurrentTokenPrice() private constant returns (uint256 currentPrice) {
      if (block.number < firstXRChangeBlock) {
        return privateExchangeRate;
      } else if (block.number < secondXRChangeBlock) {
        return firstExchangeRate;
      } else if (block.number < thirdXRChangeBlock) {
        return secondExchangeRate;
      } else {
        return thirdExchangeRate;
      }
    }
}
