# BNB Chain MCP Skill (OpenClaw Adaptation)

## Purpose

Use this skill when working with BNB Chain networks (BSC, opBNB) or Greenfield storage. Provides guidance for connecting to the BNB Chain MCP server and using its tools for:

- Blocks, transactions, network info
- Wallet balances & transfers (native, ERC20, NFT, ERC1155)
- Smart contract reads & writes
- Token & NFT metadata
- ERC-8004 agent registration
- Greenfield storage operations

## Installation

The BNB Chain MCP server is a Node.js tool:

```bash
npx @bnb-chain/mcp@latest
```

This installs and runs the MCP server, which speaks JSON-RPC over stdio or SSE.

### As an MCP Client (Cursor, Claude Desktop)

Add to your MCP config (e.g., `claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "bnbchain-mcp": {
      "command": "npx",
      "args": ["-y", "@bnb-chain/mcp@latest"],
      "env": {
        "PRIVATE_KEY": ""
      }
    }
  }
}
```

For SSE mode: `["-y", "@bnb-chain/mcp@latest", "--sse"]` and provide `url`.

## Credentials

- **Read-only** (blocks, balances, contract reads): No PRIVATE_KEY needed.
- **Write operations** (transfers, contract writes, ERC-8004 registration, Greenfield writes): Set `PRIVATE_KEY` in the MCP server environment. Never expose in chat.

Default RPC endpoints are built-in for supported chains. No extra config needed.

## Supported Networks

Get list via tool: `get_supported_networks`

Common ones:
- `bsc` — BNB Smart Chain (mainnet)
- `opbnb` — opBNB
- `ethereum` — Ethereum mainnet
- `base` — Base
- `arbitrum` — Arbitrum One
- And others (chain IDs also accepted)

**Note:** For write tools, `network` parameter is REQUIRED. Do not default to mainnet; ask user to confirm.

## Core Tools Reference

### Blocks
- `get_latest_block` — latest block number & hash
- `get_block_by_number` — block details by number
- `get_block_by_hash` — block details by hash

### Transactions
- `get_transaction` — fetch by hash
- `get_transaction_receipt` — receipt by hash
- `estimate_gas` — estimate gas for a transaction

### Network
- `get_chain_info` — chain ID, block number, RPC URL
- `get_supported_networks` — list available networks

### Wallet & Balances
- `get_native_balance` — BNB/ETH/etc balance (by address or privateKey)
- `get_erc20_balance` — ERC20 token balance
- `get_address_from_private_key` — derive address

**Write** (require PRIVATE_KEY):
- `transfer_native_token` — send native coins
- `transfer_erc20` — send ERC20 tokens
- `approve_token_spending` — approve spender
- `transfer_nft` — transfer ERC721
- `transfer_erc1155` — transfer ERC1155

### Contracts
- `is_contract` — check if address is contract or EOA
- `read_contract` — call view/pure function (provide ABI)
- `write_contract` — **(write)** state-changing call (requires PRIVATE_KEY)

### Tokens (ERC20)
- `get_erc20_token_info` — name, symbol, decimals

### NFTs (ERC721 / ERC1155)
- `get_nft_info` — metadata, owner
- `get_erc1155_token_metadata` — ERC1155 metadata
- `get_nft_balance` / `get_erc1155_balance` — balance queries

### ENS
- `resolve_ens` — resolve ENS name (Ethereum only)

### ERC-8004 Agent Registration
- `register_erc8004_agent` — **(write)** register as an agent
- `set_erc8004_agent_uri` — **(write)** update agent metadata URI
- `get_erc8004_agent` — query agent info
- `get_erc8004_agent_wallet` — get agent's wallet address

### Greenfield Storage
- `gnfd_bucket_*` — bucket operations (create, list, delete)
- `gnfd_object_*` — object operations (put, get, delete, list)
- `gnfd_payment_*` — payment account management

Refer to `references/greenfield-tools-reference.md` for details.

## Prompts (High-Level Workflows)

The MCP server provides built-in prompts:

- `analyze_block` — analyze a block's contents
- `analyze_transaction` — analyze a transaction (receipt, calls)
- `analyze_address` — analyze an EVM address (activity, holdings)
- `interact_with_contract` — guidance for interacting with a contract
- `explain_evm_concept` — explain EVM concepts
- `compare_networks` — compare EVM networks
- `analyze_token` — analyze an ERC20 or NFT token
- `how_to_register_mcp_as_erc8004_agent` — agent registration guide

Use prompt names when the user asks for analysis or guidance.

## Safety & Best Practices

1. **Confirm before sending transactions** — For any transfer, contract write, or approve, confirm recipient, amount, network, and consequences with the user.
2. **Network required for writes** — Never default to a network for writes; explicitly ask if not provided.
3. **Private keys** — Only set in MCP server environment, never echoed or logged.
4. **ERC-8004 agentURI** — Provide JSON metadata per Agent Metadata Profile (name, description, image, services).

## Integration Notes for OpenClaw

OpenClaw can call MCP tools by spawning the MCP server as a subprocess and communicating via stdio (JSON-RPC). However, this requires implementing the MCP client protocol.

**Alternative simpler approach:** Use direct RPC calls via `curl` or `cast` for read-only queries when only basic data is needed. For write operations, consider using dedicated SDKs or wallet signing outside of OpenClaw for security.

If MCP integration is needed:
1. spawn `npx @bnb-chain/mcp@latest` with `stdio`
2. send JSON-RPC requests as per MCP specification
3. handle notifications and responses

## Reference Material

- BNB Chain MCP repo: https://github.com/bnb-chain/bnbchain-mcp
- npm package: `@bnb-chain/mcp`
- ERC-8004: Identity Registry standard for agents
- Agent Metadata Profile: agentURI format

## Quick Examples

Get BSC latest block:
```bash
npx @bnb-chain/mcp@latest get_latest_block --network bsc
```

Get BUSD token info on BSC:
```bash
npx @bnb-chain/mcp@latest get_erc20_token_info --token-address 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56 --network bsc
```

Get native balance (read-only):
```bash
npx @bnb-chain/mcp@latest get_native_balance --address 0xYourAddress --network bsc
```

## Differences from OKX DEX Market Skill

- This skill uses BNB Chain's own MCP server, not a third-party API.
- Provides lower-level RPC access and contract interaction.
- Does not include market data (prices, volume, K-lines) — those require exchange APIs or oracles.
- For on-chain token analytics (holders, transfers), you would use `get_erc20_balance` for a specific address or scan events via `get_logs` (advanced).

For Pump.fun-style meme token analytics on BSC, you would need to combine:
- MCP `get_erc20_token_info` for metadata
- Custom RPC queries to get Transfer events and aggregate top holders
- Explorer APIs (BscScan) for holder distribution (rate-limited)

Alternatively, use a specialized analytics API.
