module.exports = {
  networks: {
    // ganache: {
    //   host: "localhost",
    //   port: 7545,
    //   network_id: "*",
    // },

    development: {
      host: "localhost",
      port: 9545,
      network_id: "*",
    },
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    timeout: 100000
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.16",      // Fetch exact version from solc-bin (default: truffle's version)
      // docker: true,        // Use ".0.51" you've installed locally with docker (default: false)
      // settings: {          // See the solidity docs for advice about optimization and evmVersion
      //  optimizer: {
      //    enabled: true,
      //    runs: 200
      // },
      //  evmVersion: "byzantium"
      // }
    }
  }
};