// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FlightSuretyData is AccessControl, Ownable, Pausable {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    /********************************************************************************************/
    /*                                       DEFINITIONS                                        */
    /********************************************************************************************/

    enum AirlineState {
        Pending,
        Rejected,
        Approved,
        Funded
    }

    struct Airline {
        string name;
        bool exists;
        AirlineState state;
    }

    struct Vote {
        bool vote;
        bool exists;
    }

    struct Voting {
        mapping(address => Vote) votes;
        Counters.Counter count;
    }

    struct Flight {
        address airline;
        string name;
        uint256 createdAt;
        uint256 scheduledTo;
        bool exists;
        uint8 state;
    }

    struct Insurance {
        Policy[] policies;
        uint256 total;
        bool exists;
    }

    struct Policy {
        uint256 amount;
    }

    /********************************************************************************************/
    /*                                       CONSTANTS                                          */
    /********************************************************************************************/

    bytes32 private constant AUTHORIZED_CALLER_ROLE = keccak256("AUTHORIZED_CALLER_ROLE");   // Role to define who can call the contract functions

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    Counters.Counter private approvedAirlinesCount;                             // Number of registered airlines

    mapping(address => Airline) private airlines;                               // All the airlines
    mapping(address => Voting) private consensus;                               // All the airlines
    mapping(bytes32 => Flight) private flights;                                 // All the flights
    mapping(bytes32 => mapping(address => Insurance)) private flightInsurances; // All the flight insurances
    mapping(bytes32 => address[]) private flightPassengers;                     // All the passengers of a flight that have bought an insurance
    mapping(address => uint256) private passengersCredits;                      // All the passengers of a flight that have bought an insurance

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    event AirlineCreated(address indexed airline);
    event AirlineApproved(address indexed airline);
    event AirlineRejected(address indexed airline);
    event AirlineFunded(address indexed airline);
    event AirlineVoted(address indexed voter, address indexed airline, bool vote);

    event FlightRegistered(bytes32 indexed key);
    event FlightUpdated(bytes32 indexed key, uint8 state);

    event InsurancePurchased(bytes32 indexed flight, address indexed passenger);

    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor(address airline, string memory name) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AUTHORIZED_CALLER_ROLE, msg.sender);
        _setUpInitialAirline(airline, name);
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the caller to be registered as an authorized contact
    */
    modifier whenAuthorized() {
        require(hasRole(AUTHORIZED_CALLER_ROLE, msg.sender), "Caller is not authorized");
        _;
    }

    /**
    * @dev Modifier that requires the "Airline" to be not yet registered
    */
    modifier whenNewAirline(address airline)
    {
        require(!airlines[airline].exists, "Airline already registered");
        _;
    }

    /**
    * @dev Modifier that requires the "Airline" to be already registered
    */
    modifier whenAirlineExists(address airline)
    {
        require(airlines[airline].exists, "Airline not yet registered");
        _;
    }

    /**
    * @dev Modifier that requires the "Airline" to the in the "Pending" state
    */
    modifier whenAirlinePending(address airline)
    {
        require(airlines[airline].state == AirlineState.Pending, "Airline is not open for voting");
        _;
    }

    /**
    * @dev Modifier that requires the "Airline" to the in the "Funded" state
    */
    modifier whenAirlineFunded(address airline)
    {
        require(airlines[airline].state == AirlineState.Funded, "Airline is not yet active. It has to provide some fund first");
        _;
    }

    /**
    * @dev Modifier that requires the caller to be voting for the first time for the "Airline"
    */
    modifier whenNewVoter(address voter, address airline)
    {
        require(!consensus[airline].votes[voter].exists, "Caller already voted for this airline");
        _;
    }

    /**
    * @dev Modifier that requires the "Flight" not yet be registered
    */
    modifier whenNewFlight(address airline, string memory flight, uint256 timestamp)
    {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        require(!flights[key].exists, "Flight already registered");
        _;
    }

    /**
    * @dev Modifier that requires the "Flight" to be already registered
    */
    modifier whenFlightExists(address airline, string memory flight, uint256 timestamp)
    {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        require(flights[key].exists, "Flight not yet registered");
        _;
    }

    /**
    * @dev Modifier that requires the "Passenger" account to be the function caller
    */
    modifier whenPassengerHasCredits(address passenger)
    {
        require(passengersCredits[passenger] != 0, "Caller has no credits to withdraw");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Authorize the caller to call the contract
    */
    function authorizeCaller(address caller)
        public
        onlyOwner
    {
        grantRole(AUTHORIZED_CALLER_ROLE, caller);
    }

    /**
    * @dev Unauthorize the caller to call the contract
    */
    function unauthorizeCaller(address caller)
        public
        onlyOwner
    {
        revokeRole(AUTHORIZED_CALLER_ROLE, caller);
    }

    /**
    * @dev Pause the contract
    *
    * When the contract is paused, all write transactions can be invoked
    */
    function pause()
        external
        whenNotPaused
        whenAuthorized
    {
        _pause();
    }

    /**
    * @dev Unpause the contract
    *
    * When the contract is paused, all write transactions except for this one will fail
    */
    function unpause()
        external
        whenPaused
        whenAuthorized
    {
        _unpause();
    }

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */
    function isOperational()
        public
        view
        returns(bool)
    {
        return !paused();
    }

    /**
    * @dev Get operating status of airline
    *
    * @return A bool that is the current operating status of the airline
    */
    function isArlineOperational(address airline)
        view
        external
        whenAuthorized
        returns(bool)
    {
        return airlines[airline].exists && airlines[airline].state == AirlineState.Funded;
    }

    /**
    * @dev Checks the existence of the airline
    *
    * @return A bool that represents the non existence of the airline
    */
    function isNewAirline(address airline)
        view
        external
        whenAuthorized
        returns(bool)
    {
        return !airlines[airline].exists;
    }

    /**
    * @dev Checks the existence of the airline
    *
    * @return A bool that represents the existence of the airline
    */
    function isAirline(address airline)
        view
        external
        whenAuthorized
        returns(bool)
    {
        return airlines[airline].exists;
    }

    /**
    * @dev Get the current status of an airline
    *
    * @return The state enum of the airline
    */
    function getAirLineState(address airline)
        view
        external
        whenAuthorized
        returns(AirlineState)
    {
        return airlines[airline].state;
    }

    /**
    * @dev Get the current status of an airline
    *
    * @return The state enum of the airline
    */
    function getFlightState(address airline, string memory flight, uint256 timestamp)
        view
        external
        whenAuthorized
        whenFlightExists(airline, flight, timestamp)
        returns(uint8)
    {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        return flights[key].state;
    }

    /**
    * @dev Checks the existence of the flight
    *
    * @return A bool that represents the existence of the flight
    */
    function isNewFlight(address airline, string memory flight, uint256 timestamp)
        view
        external
        whenAuthorized
        returns(bool)
    {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        return !flights[key].exists;
    }

    /**
    * @dev Checks the existence of the flight
    *
    * @return A bool that represents the existence of the flight
    */
    function getAvailableCredit(address passenger)
        view
        external
        whenAuthorized
        returns(uint256)
    {
        return passengersCredits[passenger];
    }

    /**
    * @dev Get the number of approved airlines
    *
    * @return A number that is the current number of approved airlines
    */
    function getApprovedAirlinesCount()
        view
        external
        whenAuthorized
        returns (uint256)
    {
        return approvedAirlinesCount.current();
    }

    /**
    * @dev Get the number of votes for an "Airline"
    *
    * @return A number that is the current number of arline votes
    */
    function getAirlineVoting(address airline)
        view
        external
        whenAuthorized
        whenAirlineExists(airline)
        returns (uint256)
    {
        return consensus[airline].count.current();
    }

    /**
    * @dev Generates a flight key
    *
    * @return A keccak256 hash
    */
    function getFlightKey(address airline,
                          string memory flight,
                          uint256 timestamp)
        pure
        internal
        returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Vote for an airline
    */
    function _vote(address voter, address airline, bool approve)
        private
    {
        Voting storage voting = consensus[airline];

        voting.votes[voter].vote = approve;
        voting.votes[voter].exists = true;
        voting.count.increment();

        emit AirlineVoted(voter, airline, approve);
    }

    function _setUpInitialAirline(address airline, string memory name)
        private
    {
        airlines[airline] = Airline({
            name: name,
            exists: true,
            state: AirlineState.Funded
        });

        approvedAirlinesCount.increment();
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */   
    function registerAirline(address airline, string memory name)
        external
        whenNotPaused
        whenAuthorized
        whenNewAirline(airline)
    {
        airlines[airline] = Airline({
            name: name,
            exists: true,
            state: AirlineState.Pending
        });

        Voting storage newVoting = consensus[airline];
        newVoting.count.reset();

        emit AirlineCreated(airline);
    }

    /**
    * @dev Approve an airline without multi party consensus
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function approveAirlineWithoutConsensus(address airline)
        external
        whenNotPaused
        whenAuthorized
        whenAirlineExists(airline)
        whenAirlinePending(airline)
    {
        airlines[airline].state = AirlineState.Approved;
        approvedAirlinesCount.increment();

        emit AirlineApproved(airline);
    }

    /**
    * @dev Vote for an airline to be approved
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function approveAirline(address voter, address airline)
        external
        whenNotPaused
        whenAuthorized
        whenAirlineExists(airline)
        whenAirlinePending(airline)
        whenNewVoter(voter, airline)
    {
        _vote(voter, airline, true);
    }

    /**
    * @dev Vote for an airline to be rejected
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function rejectAirline(address voter, address airline)
        external
        whenNotPaused
        whenAuthorized
        whenAirlineExists(airline)
        whenAirlinePending(airline)
        whenNewVoter(voter, airline)
    {
        _vote(voter, airline, false);
    }

    /**
   * @dev Finalize the multi party consensus for an Airline approval
    *      Can only be called from FlightSuretyApp contract
    */
    function setAirlineConsensusApproval(address airline)
        external
        whenNotPaused
        whenAuthorized
        whenAirlineExists(airline)
    {
        airlines[airline].state = AirlineState.Approved;
        approvedAirlinesCount.increment();

        emit AirlineApproved(airline);
    }

    /**
  * @dev Finalize the multi party consensus for an Airline rejection
    *      Can only be called from FlightSuretyApp contract
    */
    function setAirlineConsensusRejection(address airline)
        external
        whenNotPaused
        whenAuthorized
        whenAirlineExists(airline)
    {
        airlines[airline].state = AirlineState.Rejected;
        emit AirlineRejected(airline);
    }

    /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */
    function fundAirline(address airline)
        external
        payable
        whenAuthorized
        whenAirlineExists(airline)
    {
        airlines[airline].state = AirlineState.Funded;

        emit AirlineFunded(airline);
    }

    /**
    * @dev Add a flight to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function registerFlight(address airline,
                            string memory flight,
                            uint256 timestamp)
        external
        whenNotPaused
        whenAuthorized
        whenAirlineExists(airline)
        whenAirlineFunded(airline)
        whenNewFlight(airline, flight, timestamp)
    {
        bytes32 key = getFlightKey(airline, flight, timestamp);

        flights[key] = Flight({
            airline: airline,
            name: flight,
            createdAt: block.timestamp,
            scheduledTo: timestamp,
            exists: true,
            state: 0
        });

        emit FlightRegistered(key);
    }

    /**
    * @dev Add a flight to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function updateFlight(address airline,
                          string memory flight,
                          uint256 timestamp,
                          uint8 state)
        external
        whenNotPaused
        whenAuthorized
        whenAirlineExists(airline)
        whenAirlineFunded(airline)
        whenFlightExists(airline, flight, timestamp)
    {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        flights[key].state = state;

        emit FlightUpdated(key, state);
    }

   /**
    * @dev Buy insurance for a flight
    *
    */   
    function buyInsurance(address passenger,
                          uint256 amount,
                          address airline,
                          string memory flight,
                          uint256 timestamp)
        external
        payable
        whenNotPaused
        whenAuthorized
        whenAirlineExists(airline)
        whenAirlineFunded(airline)
        whenFlightExists(airline, flight, timestamp)
    {
        bytes32 key = getFlightKey(airline, flight, timestamp);

        if (!flightInsurances[key][passenger].exists) {
            flightPassengers[key].push(passenger);
        }

        flightInsurances[key][passenger].total = flightInsurances[key][passenger].total.add(amount);
        flightInsurances[key][passenger].exists = true;
        flightInsurances[key][passenger].policies.push(Policy({
            amount: amount
        }));

        emit InsurancePurchased(key, passenger);
    }

    /**
     *  @dev Credits payouts to policy holders
     */
    function creditPolicyHolders(address airline,
                                 string memory flight,
                                 uint256 timestamp)
        external
        whenNotPaused
        whenAuthorized
        whenFlightExists(airline, flight, timestamp)
    {
        bytes32 key = getFlightKey(airline, flight, timestamp);
        address[] memory passengers = flightPassengers[key];

        for (uint i=0;i<passengers.length;i++) {
            address passenger = passengers[i];

            uint256 insuranceTotal = flightInsurances[key][passenger].total;
            uint256 creditAmount = insuranceTotal.mul(15).div(10);
            uint256 existingCredit = passengersCredits[passenger];

            passengersCredits[passenger] = existingCredit.add(creditAmount);
        }
    }
    

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay(address passenger)
        external
        whenNotPaused
        whenAuthorized
        whenPassengerHasCredits(passenger)
    {
        passengersCredits[passenger] = 0;
    }

    /********************************************************************************************/
    /*                                       FALLBACK FUNCTIONS                                 */
    /********************************************************************************************/

    fallback()
        external
        payable
    {
    }

    receive()
        external
        payable
    {
    }
}

