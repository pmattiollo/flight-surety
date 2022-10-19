// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./FlightSuretyData.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp is Ownable, Pausable {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       CONSTANTS                                          */
    /********************************************************************************************/

    uint256 private constant MIN_REQUIRED_FUND = 10 ether;                                  // Minimum required fund for an airline to participate in the contract
    uint256 private constant MAX_INSURANCE_SPENT = 1 ether;                                 // Maximum price that a passenger can pay for an insurance
    uint8 private constant MIN_REQUIRED_APPROVALS_PERCENTAGE = 50;                          // Minimum required percentage for approvals to accept a new airline
    uint8 private constant MAX_AIRLINES_WITHOUT_CONSENSUS = 4;                              // Maximum number of airlines that can be registered without multi-party consensus
    bytes32 private constant AUTHORIZED_CALLER_ROLE = keccak256("AUTHORIZED_CALLER_ROLE");  // Role to define who can call the contract functions
    bytes32 private constant AIRLINE_ROLE = keccak256("AIRLINE_ROLE");                      // Role to define an airline
    bytes32 private constant PASSENGER_ROLE = keccak256("PASSENGER_ROLE");                  // Role to define a passenger

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    FlightSuretyData private dataContract;  // Data contract


    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor(address payable dataContractAddress)
    {
        dataContract = FlightSuretyData(dataContractAddress);
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in
    *      the event there is an issue that needs to be fixed
    */
    modifier whenOperational()
    {
        require(isOperational(), "Pausable: paused");
        _;
    }

    /**
    * @dev Modifier that requires the "Airline" account to be the function caller
    */
    modifier whenAirline()
    {
        require(dataContract.isAirline(msg.sender), "Caller is not an airline");
        _;
    }

    /**
    * @dev Modifier that requires the "Airline" to be operational
    */
    modifier whenAirlineOperational(address airline)
    {
        require(dataContract.isArlineOperational(airline), "Airline is not yet operational. It requires funding");
        _;
    }

    /**
    * @dev Modifier that requires the "Airline" to be not yet registered
    */
    modifier whenNewAirline(address airline)
    {
        require(dataContract.isNewAirline(airline), "Airline already registered");
        _;
    }

    /**
    * @dev Modifier that requires the "Flight" not yet be registered
    */
    modifier whenNewFlight(address airline, string memory flight, uint256 timestamp)
    {
        require(dataContract.isNewFlight(airline, flight, timestamp), "Flight already registered");
        _;
    }

    /**
    * @dev Modifier that requires the "Flight" to be already registered
    */
    modifier whenFlightExists(address airline, string memory flight, uint256 timestamp)
    {
        require(!dataContract.isNewFlight(airline, flight, timestamp), "Flight is not registered");
        _;
    }

    /**
    * @dev Modifier that requires a minimum payment to be reached for funding an airline
    */
    modifier whenMinimumFund()
    {
        require(msg.value >= MIN_REQUIRED_FUND, "Minimum amount is 10 ether");
        _;
    }

    /**
    * @dev Modifier that requires the "Passenger" account to be the function caller
    */
    modifier whenPassengerHasCredits()
    {
        require(dataContract.getAvailableCredit(msg.sender) > 0, "Caller has no credits to withdraw");
        _;
    }

    /**
    * @dev Modifier that requires the maximum price for an insurance is not reached
    */
    modifier whenMaximumInsurancePriceIsNotReached()
    {
        require(msg.value <= MAX_INSURANCE_SPENT, "Maximum insurance price is 1 ether");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Pause the contract
    *
    * When the contract is paused, all write transactions can be invoked
    */
    function pause()
        public
        onlyOwner
        whenNotPaused
    {
        dataContract.pause();
        _pause();
    }

    /**
    * @dev Unpause the contract
    *
    * When the contract is paused, all write transactions except for this one will fail
    */
    function unpause()
        public
        onlyOwner
        whenNotPaused
    {
        dataContract.unpause();
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
        return !paused() && dataContract.isOperational();
    }

    /**
    * @dev Checks whether the airline registration requires multipart consensus or not
    */
    function _doesNotRequireMultipartyConsensus()
        private
        view
        returns(bool)
    {
        return dataContract.getApprovedAirlinesCount() < MAX_AIRLINES_WITHOUT_CONSENSUS;
    }

    /**
   * @dev Checks the voting status to identify whether the airline is approved or rejected
    */
    function _checkVotingStatus(address airline)
        private
    {
        uint256 numberOfApprovedAirlines = dataContract.getApprovedAirlinesCount();
        uint256 numberOfAirlineVotes = dataContract.getAirlineVoting(airline);

        if (_reachedRequiredConsensus(numberOfAirlineVotes, numberOfApprovedAirlines)) {
            dataContract.setAirlineConsensusApproval(airline);
        } else if (numberOfAirlineVotes == numberOfApprovedAirlines) {
            dataContract.setAirlineConsensusRejection(airline);
        }
    }

    /**
    * @dev Checks whether the consensus reached the minimum required number of votes to approve the airline
    */
    function _reachedRequiredConsensus(uint256 votes, uint256 numberOfApprovedAirlines)
        private
        pure
        returns(bool)
    {
        return ((votes * 100) / numberOfApprovedAirlines) >= MIN_REQUIRED_APPROVALS_PERCENTAGE;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

  
    /**
    * @dev Add an airline to the registration queue
    *
    */
    function registerAirline(address airline,
                             string memory name)
        external
        whenAirlineOperational(msg.sender)
        whenNewAirline(airline)
        returns (FlightSuretyData.AirlineState)
    {
        dataContract.registerAirline(airline, name);

        if (_doesNotRequireMultipartyConsensus()) {
            dataContract.approveAirlineWithoutConsensus(airline);
        }

        return dataContract.getAirLineState(airline);
    }

    /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */
    function fundAirline()
        external
        payable
        whenOperational
        whenAirline
        whenMinimumFund
    {
        dataContract.fundAirline(msg.sender);
    }

    /**
    * @dev Vote for an airline to be approved or rejected
    *
    */
    function voteForAirline(address airline, bool approve)
        external
        whenOperational
        whenAirline
        whenAirlineOperational(msg.sender)
    {
        if (approve) {
            dataContract.approveAirline(msg.sender, airline);
        } else {
            dataContract.rejectAirline(msg.sender, airline);
        }

        _checkVotingStatus(airline);
    }

    /**
    * @dev Register a future flight for insuring.
    *
    */  
    function registerFlight(address airline,
                            string memory flight,
                            uint256 timestamp)
        external
        whenOperational
        whenAirlineOperational(airline)
        whenNewFlight(airline, flight, timestamp)
    {
        dataContract.registerFlight(airline, flight, timestamp);
    }
    
    /**
    * @dev Called after oracle has updated flight status
    *
    */  
    function processFlightStatus(address airline,
                                 string memory flight,
                                 uint256 timestamp,
                                 uint8 statusCode)
        internal
    {
        if (statusCode == STATUS_CODE_UNKNOWN
            || dataContract.getFlightState(airline, flight, timestamp) != STATUS_CODE_UNKNOWN) {
            return;
        }

        dataContract.updateFlight(airline, flight, timestamp, statusCode);

        if (statusCode == STATUS_CODE_LATE_AIRLINE) {
            dataContract.creditPolicyHolders(airline, flight, timestamp);
        }
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(address airline,
                               string memory flight,
                               uint256 timestamp)
        external
        whenOperational
        whenFlightExists(airline, flight, timestamp)
    {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));

        ResponseInfo storage response = oracleResponses[key];
        response.requester = msg.sender;
        response.isOpen = true;

        emit OracleRequest(index, airline, flight, timestamp);
    }

    /**
    * @dev Buy insurance for a flight
    *
    */
    function buyInsurance(address airline,
                          string memory flight,
                          uint256 timestamp)
        external
        payable
        whenOperational
        whenFlightExists(airline, flight, timestamp)
        whenMaximumInsurancePriceIsNotReached
    {
        dataContract.buyInsurance(msg.sender, msg.value, airline, flight, timestamp);
    }

    /**
    *  @dev Claim passenger payout and transfers eligible payout funds to insuree
    *
    */
    function claimInsurancePayout()
        external
        whenOperational
        whenPassengerHasCredits
    {
        uint256 amount = dataContract.getAvailableCredit(msg.sender);
        dataContract.pay(msg.sender);
        payable(msg.sender).transfer(amount);
    }


// region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;    

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;        
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                        // This lets us group responses and identify
                                                        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle()
        external
        payable
    {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
                                        isRegistered: true,
                                        indexes: indexes
                                    });
    }

    function getMyIndexes()
        view
        external
        returns(uint8[3] memory)
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(uint8 index,
                                  address airline,
                                  string memory flight,
                                  uint256 timestamp,
                                  uint8 statusCode)
        external
    {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");

        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp)); 
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }


    function getFlightKey(address airline,
                          string memory flight,
                          uint256 timestamp)
        pure
        internal
        returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account)
        internal
        returns(uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);
        
        indexes[1] = indexes[0];
        while(indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account)
        internal
        returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

// endregion

}   
