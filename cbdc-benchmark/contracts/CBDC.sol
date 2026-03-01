// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CBDC - Central Bank Digital Currency Token
 * @notice Minimal ERC-20-like contract for benchmarking
 *         Operations: mint, transfer, balanceOf
 */
contract CBDC {
    string  public name     = "Digital Currency";
    string  public symbol   = "DCBDC";
    uint8   public decimals = 18;
    uint256 public totalSupply;

    address public immutable centralBank;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed to, uint256 value);
    event Burn(address indexed from, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    modifier onlyCentralBank() {
        require(msg.sender == centralBank, "CBDC: caller is not central bank");
        _;
    }

    constructor() {
        centralBank = msg.sender;
    }

    // ─── Core benchmark operations ────────────────────────────────────────────

    /**
     * @notice Mint new CBDC tokens (central bank only)
     */
    function mint(address to, uint256 amount) external onlyCentralBank {
        require(to != address(0), "CBDC: mint to zero address");
        _balances[to] += amount;
        totalSupply    += amount;
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Transfer CBDC between addresses
     */
    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "CBDC: transfer to zero address");
        require(_balances[msg.sender] >= amount, "CBDC: insufficient balance");
        unchecked {
            _balances[msg.sender] -= amount;
            _balances[to]         += amount;
        }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Check balance of an address
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    // ─── ERC-20 extensions ────────────────────────────────────────────────────

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_allowances[from][msg.sender] >= amount, "CBDC: allowance exceeded");
        require(_balances[from] >= amount, "CBDC: insufficient balance");
        unchecked {
            _allowances[from][msg.sender] -= amount;
            _balances[from]               -= amount;
            _balances[to]                 += amount;
        }
        emit Transfer(from, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @notice Burn tokens (for settlement finality simulation)
     */
    function burn(uint256 amount) external {
        require(_balances[msg.sender] >= amount, "CBDC: insufficient balance");
        unchecked { _balances[msg.sender] -= amount; }
        totalSupply -= amount;
        emit Burn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    /**
     * @notice Batch mint for pre-funding benchmark accounts
     */
    function batchMint(address[] calldata recipients, uint256 amount) external onlyCentralBank {
        uint256 len = recipients.length;
        require(len <= 500, "CBDC: batch too large");
        uint256 total = amount * len;
        totalSupply += total;
        for (uint256 i = 0; i < len;) {
            _balances[recipients[i]] += amount;
            emit Transfer(address(0), recipients[i], amount);
            unchecked { ++i; }
        }
    }
}
