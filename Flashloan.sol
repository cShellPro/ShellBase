pragma solidity ^0.6.6;

// test contract from:
// https://cryptomarketpool.com/flash-loan-arbitrage-on-uniswap-and-sushiswap/

import './UniswapV2Library.sol';
import './IUniswapV2Router02.sol';
import './IUniswapV2Router.sol';
import './IUniswapV2Callee.sol';
import './IUniswapV2Pair.sol';
import './IUniswapV2Factory.sol';
import './interfaces/IERC20.sol';

// deployment addresses
// Uniswap factory:
// 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
// Token:
//    WETH = 0xA2881A90Bf33F03E7a3f803765Cd2ED5c8928dFb
//    DAI  = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11

// Sushiswap router:
// 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
// Token:
//    WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
//    DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F

// uniPair   = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc
// sushiPair = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0


contract Flashloan {
  //uniswap factory address
  address public uniSwapRouter;

  //create pointer to the sushiswapRouter
  IUniswapV2Router02 public sushiSwapRouter;  

  // trade deadline used for expiration
  // uint constant deadline = now + 100;
  uint constant deadline = 100;

  /*
  constructor(address _factory, address _sushiSwapRouter) public {
    // create uniswap factory
    uniSwapRouter = _factory;  

    // create sushiswapRouter 
    sushiSwapRouter = IUniswapV2Router02(_sushiSwapRouter);
  }
  */

  // trader needs to monitor for arbitrage opportunities with a bot or script
  // this is the function that trader will call when an arbitrage opportunity exists
  // tokens are the addresses that you want to trade
  // this first function will create the flash loan on uniswap
  // one of the amounts will be 0 and the other amount will be the amount you want to borrow
function executeTrade(address _factory, address _sushiSwapRouter, address token0, address token1, uint amount0, uint amount1) external {
    // get routerA and routerB addresses
    // create uniswap factory
    uniSwapRouter = _factory;  

    // create sushiswapRouter 
    sushiSwapRouter = IUniswapV2Router02(_sushiSwapRouter);    
    
    // get liquidity pair address for tokens on uniswap
    address pairAddress = IUniswapV2Factory(uniSwapRouter).getPair(token0, token1); 

    // make sure the pair exists in uniswap 
    require(pairAddress != address(0), 'Could not find pool on uniswap'); 

    // create flashloan 
    // create pointer to the liquidity pair address 
    // to create a flashloan call the swap function on the pair contract 
    // one amount will be 0 and the non 0 amount is for the token you want to borrow 
    // address is where you want to receive token that you are borrowing
    // bytes can not be empty.  Need to inculde some text to initiate the flash loan 
    // if bytes is empty it will initiate a traditional swap 
    IUniswapV2Pair(pairAddress).swap(amount0, amount1, address(this), bytes('flashloan'));
 }

  // After the flashloan is created the below function will be called back by Uniswap
  // Uniswap is expecting the function to be named uniswapV2Call
  // the parameters below will be sent
  // sender is the smart contract address
  // amount will be the amount borrowed from the flashloan and other amount will be 0
  // bytes is the calldata passed in above
function uniswapV2Call(address _sender, uint _amount0, uint _amount1, bytes calldata _data) external {
    // the path is the array of addresses to capture pricing information 
    address[] memory path = new address[](2); 
    
    // get the amount of tokens that were borrowed in the flash loan amount 0 or amount 1 
    // call it amountTokenBorrowed and will use later in the function 
    uint amountTokenBorrowed = _amount0 == 0 ? _amount1 : _amount0; 

    // get the addresses of the two tokens from the uniswap liquidity pool 
    address token0 = IUniswapV2Pair(msg.sender).token0(); 
    address token1 = IUniswapV2Pair(msg.sender).token1(); 

    // make sure the call to this function originated from
    // one of the pair contracts in uniswap to prevent unauthorized behavior
    require(msg.sender == UniswapV2Library.pairFor(uniSwapRouter, token0, token1), 'Invalid Request');

    // make sure one of the amounts = 0 
    require(_amount0 == 0 || _amount1 == 0);

    // create and populate path array for sushiswap.  
    // this defines what token we are buying or selling 
    // if amount0 == 0 then we are going to sell token 1 and buy token 0 on sushiswap 
    // if amount0 is not 0 then we are going to sell token 0 and buy token 1 on sushiswap 
    path[0] = _amount0 == 0 ? token1 : token0; 
    path[1] = _amount0 == 0 ? token0 : token1; 

    // create a pointer to the token we are going to sell on sushiswap 
    IERC20 token = IERC20(_amount0 == 0 ? token1 : token0);
    
    // approve the sushiSwapRouter to spend our tokens so the trade can occur             
    token.approve(address(sushiSwapRouter), amountTokenBorrowed);

    // calculate the amount of tokens we need to reimburse uniswap for the flashloan 
    uint amountRequired = UniswapV2Library.getAmountsIn(uniSwapRouter, amountTokenBorrowed, path)[0]; 
    
    // finally sell the token we borrowed from uniswap on sushiswap 
    // amountTokenBorrowed is the amount to sell 
    // amountRequired is the minimum amount of token to receive in exchange required to payback the flash loan 
    // path what we are selling or buying 
    // msg.sender address to receive the tokens 
    // deadline is the order time limit 
    // if the amount received does not cover the flash loan the entire transaction is reverted 
    uint amountReceived = sushiSwapRouter.swapExactTokensForTokens( amountTokenBorrowed, amountRequired, path, msg.sender, deadline)[1]; 

    // pointer to output token from sushiswap 
    IERC20 outputToken = IERC20(_amount0 == 0 ? token0 : token1);
  
    // amount to payback flashloan 
    // amountRequired is the amount we need to payback 
    // uniswap can accept any token as payment
    outputToken.transfer(msg.sender, amountRequired);   

    // send profit (remaining tokens) back to the address that initiated the transaction 
    outputToken.transfer(tx.origin, amountReceived - amountRequired);  
 }

     // received and callback functions
    event Received(address, uint);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    fallback() external payable {

    }
} 
