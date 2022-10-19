
var Test = require('../config/testConfig.js');
//var BigNumber = require('bignumber.js');

contract('Oracles', async (accounts) => {

  const TEST_ORACLES_COUNT = 20;

  // Watch contract events
  const STATUS_CODE_UNKNOWN = 0;
  const STATUS_CODE_ON_TIME = 10;
  const STATUS_CODE_LATE_AIRLINE = 20;
  const STATUS_CODE_LATE_WEATHER = 30;
  const STATUS_CODE_LATE_TECHNICAL = 40;
  const STATUS_CODE_LATE_OTHER = 50;

  var config;
  before('setup contract', async () => {
    config = await Test.Config(accounts);
    await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
  });

  it('can register oracles', async () => {
    // ARRANGE
    const fee = await config.flightSuretyApp.REGISTRATION_FEE.call();
    config.oracles = [];

    console.log("Accounts: ", accounts)
    // ACT
    for (let a = 1;a < TEST_ORACLES_COUNT;a++) {
      await config.flightSuretyApp.registerOracle({ from: accounts[a], value: fee, gas: '200000' });
      const result = await config.flightSuretyApp.getMyIndexes.call({ from: accounts[a] });

      config.oracles.push({
        address: accounts[a],
        indexes: [
          parseInt(result[0].toString()),
          parseInt(result[1].toString()),
          parseInt(result[2].toString())
        ]
      });

      console.log(`Oracle Registered: ${result[0]}, ${result[1]}, ${result[2]}`);
    }
  });

  it('can request flight status', async () => {
    // ARRANGE
    const flight = 'ND1309';
    const timestamp = Math.floor(Date.now() / 1000);

    await config.flightSuretyApp.registerFlight(config.firstAirline, flight, timestamp, { from: config.firstAirline });

    // ACT
    // Submit a request for oracles to get status information for a flight
    await config.flightSuretyApp.fetchFlightStatus(config.firstAirline, flight, timestamp);

    await config.flightSuretyApp.getPastEvents("OracleRequest", { fromBlock: 0, toBlock: "latest" })
        .then(log => {
          assert.equal(log[0].event, "OracleRequest", "Invalid event emitted");

          const request = log[0].returnValues;
          assert.equal(request.airline, config.firstAirline, "Airline does not match");
          assert.equal(request.flight, flight, "Flight does not match");
          assert.equal(request.timestamp, timestamp, "Timestamp does not match");
        });
  });

  it('should not accept responses from non registered oracles', async () => {
    // ARRANGE
    const flight = 'ND1310';
    const timestamp = Math.floor(Date.now() / 1000);
    const airline = config.firstAirline;
    let errorMessage = '';
    let reverted = false;

    await config.flightSuretyApp.registerFlight(airline, flight, timestamp, { from: airline });
    await config.flightSuretyApp.fetchFlightStatus(airline, flight, timestamp);

    // ACT
    try {
      await config.flightSuretyApp.submitOracleResponse(99, airline, flight, timestamp, STATUS_CODE_ON_TIME, { from: config.testAddresses[0] });
    }
    catch(e) {
      errorMessage = e.message;
      reverted = true;
    }

    // ASSERT
    assert.equal(reverted, true, "Oracle response should not be accepted");
    assert.equal(errorMessage.includes('Index does not match oracle request'), true, "Index validation didn't work");
  });

  it('should accept responses from registered oracles', async () => {
    // ARRANGE
    const flight = 'ND1311';
    const timestamp = Math.floor(Date.now() / 1000);
    const airline = config.firstAirline;
    let lastOracleRequest;
    let failedSubmissions = 0;

    await config.flightSuretyApp.registerFlight(airline, flight, timestamp, { from: airline });
    await config.flightSuretyApp.fetchFlightStatus(airline, flight, timestamp);
    await config.flightSuretyApp.getPastEvents("OracleRequest", {fromBlock: 0, toBlock: "latest"})
        .then(log => {
          lastOracleRequest = log[log.length - 1].returnValues;
        });

    const validIndex = lastOracleRequest.index;
    const acceptableOracles =  config.oracles.filter(oracle => oracle.indexes.includes(parseInt(validIndex.toString())));

    // ACT
    for (const oracle of acceptableOracles) {
      try {
        await config.flightSuretyApp.submitOracleResponse(validIndex, airline, flight, timestamp, STATUS_CODE_ON_TIME, { from: oracle.address });
      }
      catch(e) {
        failedSubmissions ++;
      }
    }

    // ASSERT
    assert.equal(failedSubmissions, 0, 'All oracle submissions should be accepted with that matched index');
  });
});
