const Test = require('../config/testConfig.js');

const AirlineStatus = {
    Pending: 0,
    Rejected: 1,
    Approved: 2,
    Funded: 3
}

contract('Flight Surety Tests', async (accounts) => {

    let config;
    before('setup contract', async () => {
        config = await Test.Config(accounts);

        await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
    });

    /****************************************************************************************/
    /* Operations and Settings                                                              */
    /****************************************************************************************/

    it(`(multiparty) has correct initial isOperational() value`, async function () {

        // Get operating status
        let status = await config.flightSuretyData.isOperational.call();
        assert.equal(status, true, "Incorrect initial operating status value");
    });

    it(`(multiparty) can block access to pause() for non-Contract Owner account`, async function () {
        // Ensure that access is denied for non-Contract Owner account
        let accessDenied = false;
        try {
            await config.flightSuretyData.pause({ from: config.testAddresses[2] });
        } catch(e) {
            accessDenied = true;
        }

        assert.equal(accessDenied, true, "Access not restricted to Contract Owner");
    });

    it(`(multiparty) can allow access to pause() for Contract Owner account`, async function () {
        // Ensure that access is allowed for Contract Owner account
        let accessDenied = false;
        try {
            await config.flightSuretyData.pause({ from: config.owner });
        } catch(e) {
            console.error("Exception: ", e);
            accessDenied = true;
        }

        assert.equal(accessDenied, false, "Access not restricted to Contract Owner");

        // Set it back for other tests to work
        await config.flightSuretyData.unpause({ from: config.owner });
    });

    it(`(multiparty) can block access to functions when paused`, async function () {
        await config.flightSuretyData.pause({ from: config.owner });

        let reverted = false;
        try {
            await config.flightSuretyData.registerAirline(config.testAddresses[2], "Test");
        } catch(e) {
            reverted = true;
        }

        assert.equal(reverted, true, "Access not blocked for requireIsOperational");

        // Set it back for other tests to work
        await config.flightSuretyData.unpause({ from: config.owner });
    });

    it('(airline) authorized caller can register an Airline', async () => {
        // ARRANGE
        const secondAirline = accounts[2];

        // ACT
        await config.flightSuretyApp.registerAirline(secondAirline, 'Second Airline', { from: config.firstAirline });

        const state = await config.flightSuretyData.getAirLineState.call(secondAirline);
        const isAirline = await config.flightSuretyData.isAirline.call(secondAirline);

        // ASSERT
        assert.equal(state, AirlineStatus.Approved, "The new airline should be registered and status Approved");
        assert.equal(isAirline, true, "An authorizes contract should be able to register another airline");
    });

    it('(airline) cannot register an Airline if not funded', async () => {
        // ARRANGE
        const thirdAirline = accounts[3];
        const fourthAirline = accounts[4];
        let reverted = false;

        // ACT
        await config.flightSuretyApp.registerAirline(thirdAirline, 'Third Airline', { from: config.firstAirline });
        let state = await config.flightSuretyData.getAirLineState.call(thirdAirline);
        try {
            await config.flightSuretyApp.registerAirline(fourthAirline, 'Fourth Airline', { from: thirdAirline });
        } catch(e) {
            reverted = true;
        }
        const isArline = await config.flightSuretyData.isAirline.call(fourthAirline);

        // ASSERT
        assert.equal(state, AirlineStatus.Approved, "The new airline should still be Approved and not yet Funded");
        assert.equal(reverted, true, "It should be reverted because airline is not yet Funded");
        assert.equal(isArline, false, "Airline should not be able to register another airline if it hasn't provided funding");
    });

    it('(airline) cannot register an Airline twice', async () => {
        // ARRANGE
        let reverted = false;

        // ACT
        try {
            await config.flightSuretyApp.registerAirline(config.firstAirline, 'First Airline Second attempt', { from: config.owner });
        } catch(e) {
            reverted = true;
        }

        // ASSERT
        assert.equal(reverted, true, "It should be reverted because airline is already registered");
    });

    it('(airline) can fund an Airline with 10 or more ether' , async () => {
        // ARRANGE
        const secondAirline = accounts[2];
        const correctAmount = web3.utils.toWei('10', "ether");
        const incorrectAmount = web3.utils.toWei('1', "ether");
        let reverted = false;

        // ACT
        try {
            await config.flightSuretyApp.fundAirline({ from: secondAirline, value: incorrectAmount });
        } catch (e) {
            reverted = true;
        }

        let beforeFundingState = await config.flightSuretyData.getAirLineState.call(secondAirline);
        await config.flightSuretyApp.fundAirline({ from: secondAirline, value: correctAmount });
        let afterFundingState = await config.flightSuretyData.getAirLineState.call(secondAirline);

        // ASSERT
        assert.equal(reverted, true, "The minimum amount for funding is 10 ether");
        assert.equal(beforeFundingState, AirlineStatus.Approved, "The new airline should still be Approved and not yet Funded");
        assert.equal(afterFundingState, AirlineStatus.Funded, "The new airline should still be Approved and not yet Funded");
    });

    it('(airline) can register and approve up to four airlines without consensus', async () => {
        // ARRANGE
        const fourthAirline = accounts[4];
        const fifthAirline = accounts[5];
        const sixthAirline = accounts[6];

        // ACT
        await config.flightSuretyApp.registerAirline(fourthAirline, "Fourth arline", { from: config.firstAirline });
        await config.flightSuretyApp.registerAirline(fifthAirline, "Fifth arline", { from: config.firstAirline });
        await config.flightSuretyApp.registerAirline(sixthAirline, "Sixth arline", { from: config.firstAirline });

        const fourthAirlineState = await config.flightSuretyData.getAirLineState.call(fourthAirline);
        const fifthAirlineState = await config.flightSuretyData.getAirLineState.call(fifthAirline);
        const sixthAirlineState = await config.flightSuretyData.getAirLineState.call(sixthAirline);

        // ASSERT
        assert.equal(fourthAirlineState, AirlineStatus.Approved, "Status should be Approved");
        assert.equal(fifthAirlineState, AirlineStatus.Pending, "Status should be Pending");
        assert.equal(sixthAirlineState, AirlineStatus.Pending, "Status should be Pending");
    });

    it('(airline) can vote for airline only if funded', async () => {
        // ARRANGE
        const thirdAirline = accounts[3];
        const fifthAirline = accounts[5];
        let reverted = false;

        // ACT
        try {
            await config.flightSuretyApp.voteForAirline(fifthAirline, true, { from: thirdAirline });
        } catch (e) {
            reverted = true;
        }

        await config.flightSuretyApp.fundAirline({ from: thirdAirline, value: web3.utils.toWei('10', "ether") });
        await config.flightSuretyApp.voteForAirline(fifthAirline, true, { from: thirdAirline });
        const secondAirlineVotes = await config.flightSuretyData.getAirlineVoting.call(fifthAirline);

        // ASSERT
        assert.equal(reverted, true, "Airline is not yet funded");
        assert.equal(secondAirlineVotes, 1, "Total of votes should be 1");
    });

    it('(airline) cannot vote twice for airline', async () => {
        // ARRANGE
        const fourthAirline = accounts[4];
        const fifthAirline = accounts[5];
        let reverted = false;

        await config.flightSuretyApp.fundAirline({ from: fourthAirline, value: web3.utils.toWei('10', "ether") });
        await config.flightSuretyApp.voteForAirline(fifthAirline, true, { from: fourthAirline });

        // ACT
        try {
            await config.flightSuretyApp.voteForAirline(fifthAirline, true, { from: fourthAirline });
        } catch (e) {
            reverted = true;
        }

        // ASSERT
        assert.equal(reverted, true, "Arline cannot vote twice");
    });

    it('(airline) can approve airline when consensus is reached', async () => {
        // ARRANGE
        const secondAirline = accounts[2];
        const thirdAirline = accounts[3];
        const fourthAirline = accounts[4];
        const seventhAirline = accounts[7];
        let reverted = false;

        // ACT
        await config.flightSuretyApp.registerAirline(seventhAirline, "Seventh Airline", { from: config.firstAirline });
        let stateBeforeVoting = await config.flightSuretyData.getAirLineState.call(seventhAirline);

        await config.flightSuretyApp.voteForAirline(seventhAirline, false, { from: config.firstAirline });
        await config.flightSuretyApp.voteForAirline(seventhAirline, true, { from: secondAirline });
        await config.flightSuretyApp.voteForAirline(seventhAirline, false, { from: thirdAirline });

        try {
            await config.flightSuretyApp.voteForAirline(seventhAirline, true, { from: fourthAirline });
        } catch (e) {
            reverted = true;
        }

        let stateAfterVoting = await config.flightSuretyData.getAirLineState.call(seventhAirline);

        // ASSERT
        assert.equal(stateBeforeVoting, AirlineStatus.Pending, 'Arline should be Pending');
        assert.equal(stateAfterVoting, AirlineStatus.Approved, 'Arline should be Approved');
        assert.equal(reverted, true, "After Approved the Arline should not be open for voting anymore");
    });

    it('(airline) airline cannot vote until is funded', async () => {
        // ARRANGE
        const sixthAirline = accounts[6];
        const seventhAirline = accounts[7];
        let reverted = false;

        // ACT
        let stateBeforeVoting = await config.flightSuretyData.getAirLineState.call(seventhAirline);
        try {
            await config.flightSuretyApp.voteForAirline(sixthAirline, true, { from: seventhAirline });
        } catch(e) {
            reverted = true;
        }

        await config.flightSuretyApp.fundAirline({ from: seventhAirline, value: web3.utils.toWei('10', 'ether') });
        await config.flightSuretyApp.voteForAirline(sixthAirline, true, { from: seventhAirline });

        // ASSERT
        assert.equal(stateBeforeVoting, AirlineStatus.Approved, 'Arline should be Approved');
        assert.equal(reverted, true, "Airline cannot vote if not funded");
    });

    it('(airline) airline cannot register flight until is funded', async () => {
        // ARRANGE
        const sixthAirline = accounts[6];
        const flight = "PPP-01";
        const timestamp = 1665864230;
        let reverted = false;

        // ACT
        try {
            await config.flightSuretyApp.registerFlight(sixthAirline, flight, timestamp, { from: config.firstAirline });
        } catch(e) {
            reverted = true;
        }

        await config.flightSuretyApp.fundAirline({ from: sixthAirline, value: web3.utils.toWei('10', 'ether') });
        await config.flightSuretyApp.registerFlight(sixthAirline, flight, timestamp, { from: config.firstAirline });
        const isNewFlight = await config.flightSuretyData.isNewFlight(sixthAirline, flight, timestamp);

        // ASSERT
        assert.equal(reverted, true, "Airline cannot register a flight if not funded");
        assert.equal(isNewFlight, false, "Flight should have been registered");
    });

    it('(insurance) passenger can buy insurance by paying up to 1 ether', async () => {
        // ARRANGE
        const sixthAirline = accounts[6];
        const flight = "PPP-02";
        const timestamp = 1665864231;
        const passenger = accounts[7];
        const amount = web3.utils.toWei('0.5', 'ether')

        // ACT
        const balanceBefore = await web3.eth.getBalance(passenger);
        await config.flightSuretyApp.registerFlight(sixthAirline, flight, timestamp, { from: sixthAirline });
        const transaction = await config.flightSuretyApp.buyInsurance(sixthAirline, flight, timestamp, { from: passenger, value: amount });
        const balanceAfter = await web3.eth.getBalance(passenger);
        const transactionCosts = transaction.receipt.gasUsed * transaction.receipt.effectiveGasPrice;

        // ASSERT
        assert.equal(balanceAfter, (balanceBefore - amount - transactionCosts), "Account balance doesn't match");
    });

    it('(insurance) a passenger cannot buy insurance by paying more than 1 ether', async () => {
        // ARRANGE
        const sixthAirline = accounts[6];
        const flight = "PPP-03";
        const timestamp = 1665864232;
        const passenger = accounts[7];
        const amount = web3.utils.toWei('1.1', 'ether')
        let reverted = false;

        await config.flightSuretyApp.registerFlight(sixthAirline, flight, timestamp, { from: sixthAirline });

        // ACT
        try {
            await config.flightSuretyApp.buyInsurance(sixthAirline, flight, timestamp, { from: passenger, value: amount });
        } catch(e) {
            reverted = true;
        }

        // ASSERT
        assert.equal(reverted, true, "Cannot buy an insurance paying more than 1 ether");
    });
});


