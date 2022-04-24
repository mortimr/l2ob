# L2OB
![tests](https://github.com/mortimr/l2ob/actions/workflows/tests.yaml/badge.svg)
![mythril](https://github.com/mortimr/l2ob/actions/workflows/mythril.yaml/badge.svg)

## 100% On-Chain Permission-Less OrderBook, using ERC1155 to mint positions

- Uses the same contract architecture as UniswapV2 (1 router (PublicLibrary), 1 factory (Printer), many pairs (Book)).
- Open orders by depositing tokens and specifying a sell price for your token.
- All positions at the same sell price are fungible and filled together.
- Get the best order info by calling `head0` or `head1`
- An experiment on L2's future capacity, and the need for an orderbook that doesn't require any off-chain lookup