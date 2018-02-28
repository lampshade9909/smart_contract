pragma solidity ^0.4.19;

/*

    This contract is intended to be a utility for ForkDelta clients.
    It may server many purposes as time goes on, but for now it is the 
    blockchain component of a client tool that assists users in withdrawing 
    from EtherDelta and/or helping to move funds to ForkDelta's future contract.
    
    The goal is for a client/web app to call functions in this contract to 
    get lots of information in one API call. Then to use that data to assist
    users in withdrawing their funds from the EtherDelta contract. For example,
    The web applicaiton could call the "allBalancesForManyAccounts" function
    and get all balances of all the user's ethereum wallets and suggest 
    withdraw transactions that withdraw 100% of his funds from EtherDelta (down 
    to the last satoshi)
    
    Some functions inspired/referenced from https://deltabalances.github.io/

	Todo:
	-Finish integrating Whitelist and Owned
    -More functional testing.
    -Test end to end with a client.
    
*/

contract Owned {
    address owner;

    function Owned() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}

contract Whitelist is Owned {
    mapping (address => bool) userAddr;
    
    function Whitelist() {
        // Whitelist the owner address
        address[] memory list = new address[](1);
        list[0] = owner;
        whitelistAddress(list);
    }

    function whitelistAddress (address[] users) 
    onlyOwner {
        for (uint i = 0; i < users.length; i++) {
            userAddr[users[i]] = true;
        }
    }
    
    function blacklistAddress (address[] users) 
    onlyOwner {
        for (uint i = 0; i < users.length; i++) {
            userAddr[users[i]] = false;
        }
    }
    
    modifier onlyWhitelist() {
        require(userAddr[msg.sender]);
        _;
    }
    
    modifier onlyOwnerOrWhitelist() {
        require(userAddr[msg.sender] || msg.sender == owner);
        _;
    }
}

contract EtherDelta {
    function balanceOf(address token, address user) public view returns (uint);
}

contract Token {
    function balanceOf(address tokenOwner) public view returns (uint balance);
    function transfer(address to, uint tokens) public returns (bool success);
}

contract BalanceChecker is Whitelist {
	function BalanceChecker() public {
	}

	// Don't accept any ETH
	function() 
	public payable {
		revert();
	}
    
	// selfdestruct for cleanup
	function destruct() 
	public onlyOwnerOrWhitelist {
		selfdestruct(owner);
	}

	// backup withdraw, if somehow ETH gets in here
	function withdraw() 
	public onlyOwnerOrWhitelist {
    	owner.transfer(this.balance);
	}

	// backup withdraw, if somehow ERC20 tokens get in here
	function withdrawToken(
	    address token, 
	    uint amount) 
	public onlyOwnerOrWhitelist {
    	require(token != address(0x0)); // use withdraw for ETH
    	require(Token(token).transfer(msg.sender, amount));
	}

	/* Get multiple token balances on EtherDelta (or similar exchange)
	   Returns array of token balances in wei units. */
	function deltaBalances(
	    address exchange, 
	    address user, 
	    address[] tokens) 
	public view returns (uint[]) {
		EtherDelta ex = EtherDelta(exchange);
	    uint[] memory balances = new uint[](tokens.length);
	    
		for(uint i = 0; i< tokens.length; i++){
			balances[i] = ex.balanceOf(tokens[i], user);
		}	
		return balances;
	}
	
	/* Get multiple token balances on EtherDelta (or similar exchange)
	   Returns array of token balances in wei units.
	   Balances in token-first order [token0ex0, token0ex1, token0ex2, token1ex0, token1ex1 ...] */
	function multiDeltaBalances(
	    address[] exchanges, 
	    address user, 
	    address[] tokens) 
	public view returns (uint[]) {
	    uint[] memory balances = new uint[](tokens.length * exchanges.length);
	    
	    for(uint i = 0; i < exchanges.length; i++){
			EtherDelta ex = EtherDelta(exchanges[i]);
    		for(uint j = 0; j< tokens.length; j++){
    			balances[(j * exchanges.length) + i] = ex.balanceOf(tokens[j], user);
    		}
	    }
		return balances;
	}
  
  /* Check the token balance of a wallet in a token contract
     Mainly for internal use, but public for anyone who thinks it is useful    */
   function tokenBalance(
       address user, 
       address token) 
   public view returns (uint) {
       //  check if token is actually a contract
        uint256 tokenCode;
        assembly { tokenCode := extcodesize(token) } // contract code size
        if(tokenCode > 0){
            Token tok = Token(token);
            //  check if balanceOf succeeds
            if(tok.call(bytes4(keccak256("balanceOf(address)")), user)) {
                return tok.balanceOf(user);
            } else {
                  return 0; // not a valid balanceOf, return 0 instead of error
            }
        } else {
            return 0; // not a contract, return 0 instead of error
        }
   }
  
    /* Check the token balances of a wallet for multiple tokens
       Uses tokenBalance() to be able to return, even if a token isn't valid 
	   Returns array of token balances in wei units. */
	function walletBalances(
	    address user, 
	    address[] tokens) 
	public view returns (uint[]) {
	    require(tokens.length > 0);
		uint[] memory balances = new uint[](tokens.length);
		
		for(uint i = 0; i< tokens.length; i++){
			if( tokens[i] != address(0x0) ) { // ETH address in Etherdelta config
			    balances[i] = tokenBalance(user, tokens[i]);
			}
			else {
			   balances[i] = user.balance; // eth balance	
			}
		}	
		return balances;
	}
	
	 /* Combine walletBalances() and deltaBalances() to get both exchange and wallet balances for multiple tokens.
	   Returns array of token balances in wei units, 2* input length.
	   even index [0] is exchange balance, odd [1] is wallet balance
	   [tok0ex, tok0, tok1ex, tok1, .. ] */
	function allBalances(
	    address exchange, 
	    address user,  
	    address[] tokens) 
    public view returns (uint[]) {
		EtherDelta ex = EtherDelta(exchange);
		uint[] memory balances = new uint[](tokens.length * 2);
		
		for(uint i = 0; i< tokens.length; i++){
		    uint j = i * 2;
			balances[j] = ex.balanceOf(tokens[i], user);
			if( tokens[i] != address(0x0) ) { // ETH address in Etherdelta config
			    balances[j + 1] = tokenBalance(user, tokens[i]);
			} else {
			   balances[j + 1] = user.balance; // eth balance	
			}
		}
		return balances; 
	}

	/* Similar to allBalances, with the addition of supporting multiple users
	   When calling this funtion through Infura, it handles a large number of 
	   users/tokens before it fails and returns 0x0 as the result. 
	   So there is some max number of arguements you can send.
	   If you reach the max, try breaking it into multiple calls (AKA don't send
	   two arrays of 100 each. instead maybe send multiple requests in parallel 
	   as 20x20 or 10x10 or 1x100...)
	   */
	function allBalancesForManyAccounts(
	    address exchange, 
	    address[] users,  
	    address[] tokens
	) public view returns (uint[]) {
		EtherDelta ex = EtherDelta(exchange);
		uint usersDataSize = tokens.length * 2;
		uint[] memory balances = new uint[](usersDataSize * users.length);
		
		for(uint k = 0; k < users.length; k++){
    		for(uint i = 0; i < tokens.length; i++){
    		    uint j = i * 2;
    			balances[(k * usersDataSize) + j] = ex.balanceOf(tokens[i], users[k]);
    			if( tokens[i] != address(0x0) ) { // ETH address in Etherdelta config
    			    balances[(k * usersDataSize) + j + 1] = tokenBalance(users[k], tokens[i]);
    			} else {
    			   balances[(k * usersDataSize) + j + 1] = users[k].balance; // eth balance	
    			}
    		}
		}
		return balances; 
	}
}