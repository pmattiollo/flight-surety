# FlightSurety

FlightSurety is a sample application project for Udacity's Blockchain course.

## Install

This repository contains Smart Contract code in Solidity (using Truffle), tests (also using Truffle), dApp scaffolding (using HTML, CSS and JS) and server app scaffolding.

To install, download or clone the repo, then:

`npm install`
`truffle compile`

## Develop Client

To run the application contract tests:

`npm run test`

To run the oracle tests, first make sure ganache is started with a minimum of 20 accounts and listen at the port 7545:

`npm run test:oracles`

## Deploy

To deploy the contracts, first make sure truffle development is started and listen at the port 9545:

`npm run deploy`

To use the dapp:

`npm run dapp`

To view dapp:

`http://localhost:8000`

To build dapp for prod:
`npm run dapp:prod`

## Develop Server

`npm run server`
`truffle test ./test/oracles.js`

Deploy the contents of the ./dapp folder

## Resources

* [How does Ethereum work anyway?](https://medium.com/@preethikasireddy/how-does-ethereum-work-anyway-22d1df506369)
* [BIP39 Mnemonic Generator](https://iancoleman.io/bip39/)
* [Truffle Framework](http://truffleframework.com/)
* [Ganache Local Blockchain](http://truffleframework.com/ganache/)
* [Remix Solidity IDE](https://remix.ethereum.org/)
* [Solidity Language Reference](http://solidity.readthedocs.io/en/v0.4.24/)
* [Ethereum Blockchain Explorer](https://etherscan.io/)
* [Web3Js Reference](https://github.com/ethereum/wiki/wiki/JavaScript-API)