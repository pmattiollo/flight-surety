const FlightSuretyApp = artifacts.require("FlightSuretyApp");
const FlightSuretyData = artifacts.require("FlightSuretyData");
const fs = require('fs');

module.exports = function(deployer, networks, accounts) {
    const owner = accounts[0];
    const firstAirline = accounts[1];

    deployer.deploy(FlightSuretyData, firstAirline, 'First Airline')
        .then(() => {
            return deployer.deploy(FlightSuretyApp, FlightSuretyData.address)
                .then(async () => {
                    let config = {
                        localhost: {
                            url: 'http://localhost:9545',
                            dataAddress: FlightSuretyData.address,
                            appAddress: FlightSuretyApp.address
                        }
                    }
                    fs.writeFileSync(__dirname + '/../src/dapp/config.json',JSON.stringify(config, null, '\t'), 'utf-8');
                    fs.writeFileSync(__dirname + '/../src/server/config.json',JSON.stringify(config, null, '\t'), 'utf-8');

                    const dataContract = await FlightSuretyData.at(FlightSuretyData.address);
                    await dataContract.authorizeCaller(FlightSuretyApp.address, { from: owner });

                    console.log("Owner: ", owner);

                    console.log("Migration done", config);
                });
    });
}