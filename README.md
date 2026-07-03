# X21

GitHub: [https://github.com/X21coin/X21](https://github.com/X21coin/X21)

X21 is a decentralized bonding-curve token experiment. The protocol mints and burns X21 through an on-chain exponential curve, keeps reserve assets in USDS/sUSDS, and exposes a static React dapp that reads contract state and trade events directly from the chain.

The project is designed to run without a traditional backend. The frontend can be deployed as static files, and protocol data comes from smart contract calls, ERC-20 balances, and `Buy` / `Sell` event logs.

## Overview

- `X21`: ERC-20 token with a hard cap of 21,000,000 X21.
- `CurveX21`: primary bonding-curve contract for buying and selling X21 with USDS.
- `EntryRouter`: optional convenience router for entering or exiting through USDC, USDT, or ETH on mainnet integrations.
- `web/`: Vite + React dapp using viem, Tailwind, and DaisyUI.

## Protocol

Core parameters:

| Item | Value |
| --- | --- |
| Token | X21 |
| Max supply | 21,000,000 X21 |
| Curve sellable supply | 20,895,000 X21 |
| Reserve target | 2,000,000 USDS |
| Buy/sell fee | 30 bps, burned as X21 |
| Reserve asset | USDS deposited into sUSDS |

Buying sends USDS into the curve, deposits the used USDS into sUSDS, mints X21 to the buyer, and burns the fee portion by never minting it to a user.

Selling burns the user's X21, redeems the curve value from sUSDS back to USDS, and sends USDS to the recipient.

## Decentralized Data

The dapp does not need an application server for protocol data.

Live stats are read from contract view functions such as:

- `spotPrice()`
- `reserveUsds()`
- `minted()`
- `ratio()`
- `formulaReserve()`
- `bonded()`

Trade history is based on chain events:

- `Buy(address indexed to, uint256 usdsIn, uint256 coinOut, uint256 burned, uint256 minted)`
- `Sell(address indexed from, uint256 coinIn, uint256 usdsOut, uint256 burned, uint256 minted)`

Current note: total volume is not stored as a dedicated contract variable. The frontend calculates volume from `Buy` and `Sell` events. This keeps the contract lean, but full historical accuracy depends on the frontend's ability to read historical logs from the selected RPC or indexing source.

## Contracts

```text
contracts/
  X21.sol              ERC-20 token, mint/burn restricted to CurveX21
  CurveX21.sol         bonding curve, reserve accounting, buy/sell events
  EntryRouter.sol      optional multi-asset entry/exit router
  mocks/
    MockUSDS.sol
    MockSUSDS.sol
```

## Frontend

```text
web/
  public/deployed.json     runtime contract address config
  src/lib/abi.js           minimal frontend ABI
  src/hooks/useProtocol.js live contract reads
  src/hooks/useTradeHistory.js event history and live event updates
  src/components/          trade, stats, history, account, docs views
```

The frontend is a static SPA. After build, `web/dist/` can be hosted by any static host.

## Setup

Install root dependencies:

```bash
npm install
```

Install frontend dependencies:

```bash
cd web
npm install
```

Create environment files from the examples when deploying to public networks:

```bash
cp .env.example .env
```

Useful variables:

- `SEPOLIA_RPC_URL`
- `MAINNET_RPC_URL`
- `DEPLOYER_KEY`
- `ETHERSCAN_API_KEY`

## Test

Run unit tests:

```bash
npm test
```

Run a mainnet fork smoke test:

```bash
npm run test:fork
```

The current unit test suite covers curve parameters, token metadata, buy mint/burn behavior, and sell redeem/burn behavior.

## Local Development

Start a local Hardhat chain:

```bash
npx hardhat node
```

Deploy local mock contracts and export addresses to `web/public/deployed.json`:

```bash
npm run deploy:local
```

Start the dapp:

```bash
cd web
npm run dev
```

Default Vite URL:

```text
http://localhost:5173
```

For local wallet testing, add the Hardhat network to MetaMask:

| Field | Value |
| --- | --- |
| RPC URL | `http://127.0.0.1:8545` |
| Chain ID | `31337` |
| Currency symbol | `ETH` |

Import one of the Hardhat test private keys printed by `npx hardhat node` to interact with the local dapp.

## Deployment

Deploy to Sepolia:

```bash
npm run deploy:sepolia
```

Deploy to mainnet:

```bash
npm run deploy:mainnet
```

Mainnet deployment should only happen after independent contract review. The contracts are immutable and do not include upgrade, pause, or admin recovery controls.

## Important Notes

- The protocol has no backend custody and no off-chain order book.
- `Buy` and `Sell` events are the canonical trade record.
- A static frontend still needs an RPC provider to read chain data.
- Some public RPC providers limit historical `eth_getLogs` ranges. For a fully backendless production frontend, use a reliable RPC provider that supports event history over the deployment range.
- `EntryRouter` is a convenience layer. The canonical curve accounting remains in `CurveX21`.

## License

MIT
