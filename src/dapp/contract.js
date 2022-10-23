import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import FlightSuretyData from '../../build/contracts/FlightSuretyData.json';
import Config from './config.json';
import Web3 from 'web3';

const BigNumber = require('bignumber.js');

export default class Contract {
    constructor(network, callback) {
        const config = Config[network];
        this.web3 = new Web3(new Web3.providers.HttpProvider(config.url));
        this.flightSuretyApp = new this.web3.eth.Contract(FlightSuretyApp.abi, config.appAddress);
        this.flightSuretyData = new this.web3.eth.Contract(FlightSuretyData.abi, config.dataAddress);
        this.airlineRegistrationFee = Web3.utils.toWei("10", "ether");
        this.owner = null;
        this.firstAirline = null;
        this.airlines = [];
        this.passengers = [];
        this.flights = [];

        this.initialize(callback);
    }

    initialize(callback) {
        this.web3.eth.getAccounts(async (error, accts) => {
            this.owner = accts[0];
            this.firstAirline = accts[1];
            let counter = 2;

            console.log('Owner', this.owner);
            console.log('First Airline', this.firstAirline);

            while (this.airlines.length < 3) {
                this.registerAirline(accts[counter], counter, (error, airlineAddress) => {
                    if (error) {
                        console.error('Error while registering airline. Skipping funding', airlineAddress);
                    } else {
                        this.fundAirline(airlineAddress);
                    }
                });

                this.airlines.push({ address: accts[counter], name: name });
                counter++;
            }

            while (this.passengers.length < 5) {
                this.registerPassenger(accts[counter]);
                counter++;
            }

            this.fetchAllFlights(callback);
        });
    }

    registerAirline(airlineAddress, counter, callback) {
        const self = this;
        const name = 'Airline ' + counter;

        return self.flightSuretyApp.methods
            .isNewAirline(airlineAddress)
            .call({ from: self.owner })
            .then(result => {
                console.log("Airline fetched with success", result);

                if (result) {
                    console.log('Registering airline:', airlineAddress);

                    self.flightSuretyApp.methods
                        .registerAirline(airlineAddress, name)
                        .send({ from: self.firstAirline, gas: 6721975 }, (error, result) => {
                            if (error) {
                                console.error("Error while registering airline", error);
                            } else {
                                console.log("Airline registered with success", result);
                            }

                            callback(error, airlineAddress);
                        });
                } else {
                    console.log('Airline is already registered, skipping...', airlineAddress);
                }
            })
            .catch(error => console.error("Error while fetching airline", error));
    }

    fundAirline(airlineAddress) {
        const self = this;

        self.flightSuretyApp.methods
            .fundAirline()
            .send({ from: airlineAddress, value: this.airlineRegistrationFee }, (error, result) => {
                if (error) {
                    console.error("Error while funding airline", error);
                } else {
                    console.log("Airline funded with success", result);
                }
            });
    }

    registerPassenger(passengerAddress) {
        this.passengers.push(passengerAddress);
    }

    isOperational(callback) {
        const self = this;

       self.flightSuretyApp.methods
            .isOperational()
            .call({ from: self.owner }, (error, result) => {
                if (error) {
                    console.error("Error while fetching operational status", error);
                } else {
                    console.log("Operational status fetched with success", result);
                }

                callback(error, result)
            });
    }

    registerFlight(airline, flight, timestamp, callback) {
        const self = this;

        self.flightSuretyApp.methods
            .registerFlight(airline, flight, timestamp)
            .estimateGas({ from: airline })
            .then(gas => {
                self.flightSuretyApp.methods
                    .registerFlight(airline, flight, timestamp)
                    .send({ from: airline, gas })
                    .then(result => {
                        console.log("Flight registered with success", result);

                        this.fetchFlight(airline, flight, timestamp, (flight) => {
                            const values = Object.values(flight);
                            this.flights.push({ airline: values[0], flight: values[1], timestamp: values[3] });

                            callback();
                        });
                    })
                    .catch(error => console.error("Error while registering flight", error));
            })
            .catch(error => console.error("Error while estimating gas for register a flight", error));

    }

    fetchFlightStatus(airline, flight, timestamp, callback) {
        const self = this;

        self.flightSuretyApp.methods
            .fetchFlightStatus(airline, flight, timestamp)
            .estimateGas({ from: airline })
            .then(gas => {
                self.flightSuretyApp.methods
                    .fetchFlightStatus(airline, flight, timestamp)
                    .call({ from: self.owner, gas })
                    .then(result => {
                        console.log("Flight status fetched with success", result);
                        callback(result);
                    })
                    .catch(error => console.error("Error while fetching flight status", error));
            })
            .catch(error => console.error("Error while estimating gas for fetching a flight status", error));
    }

    fetchFlight(airline, flight, timestamp, callback) {
        const self = this;

        console.log("Fetching flight...", airline, flight, timestamp);

        this.flightSuretyApp.methods
            .fetchFlight(airline, flight, timestamp)
            .estimateGas({ from: self.owner })
            .then(gas => {
                this.flightSuretyApp.methods
                    .fetchFlight(airline, flight, timestamp)
                    .call({ from: self.owner, gas })
                    .then(result => {
                        console.log("Flight fetched with success", result);
                        callback(result)
                    })
                    .catch(error => console.error("Error while fetching flight", error));
            })
            .catch(error => console.error("Error while estimating gas for fetching a flight", error));
    }

    fetchAllFlights(callback) {
        this.flightSuretyData.getPastEvents("FlightRegistered", { fromBlock: 0, toBlock: "latest" })
            .then(logs => {
                console.log("FlightRegistered events:", logs);

                logs.forEach(async log => {
                    const { airline, flight, timestamp } = log.returnValues;
                    this.flights.push({ airline, flight, timestamp });
                });

                if (callback) {
                    callback();
                }
            });
    }

    fetchAllAirlines() {
        this.flightSuretyData.getPastEvents("AirlineCreated", { fromBlock: 0, toBlock: "latest" })
            .then(logs => {
                console.log("AirlineCreated events:", logs);

                logs.forEach(log => {
                    const { airline } = log.returnValues;
                    console.log("Airline created: ", airline);
                });
            });
    }

    buyInsurance(passenger, airline, flight, timestamp, price, callback) {
        const self = this;
        const convertedPrice = Web3.utils.toWei(price.toString(), "ether")

        self.flightSuretyApp.methods
            .buyInsurance(airline, flight, timestamp)
            .send({ from: passenger, value: convertedPrice })
            .then(result => {
                console.log("Flight fetched with success", result);
                callback(result);
            })
            .catch(error => console.error("Error while fetching flight", error));
    }

    withdraw(passenger, callback) {
        let self = this;

        self.flightSuretyApp.methods
            .claimInsurancePayout()
            .send({ from: passenger }, callback);
    }
}