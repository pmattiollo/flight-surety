import DOM from './dom';
import Contract from './contract';

(async() => {
    let result = null;

    let contract = new Contract('localhost', () => {
        // Read transaction
        contract.isOperational((error, result) => {
            const displayDiv = DOM.elid("display-wrapper");
            const section = DOM.section();
            section.appendChild(DOM.h2("Operational Status: " + (result ? "UP" : "DOWN")));

            DOM.appendArray(displayDiv, [ section ]);
        });

        const airlinesTableBody = DOM.elid("airlines-table-body");
        const flightModalBody = DOM.elid("flight-modal-body-input-airline");
        contract.airlines.forEach((airline, index) => {
            const tr = DOM.makeElement('tr');
            const indexCol = DOM.th({ scope: 'row' }, (index + 1).toString());
            const addressCol = DOM.td({}, airline.address);
            const nameCol = DOM.td({}, airline.name);

            DOM.appendArray(tr, [ indexCol, addressCol, nameCol ]);
            DOM.appendArray(airlinesTableBody, [ tr ]);

            const option = DOM.makeElement('option', { value: airline.address }, airline.name + " (" + airline.address + ")");
            DOM.appendArray(flightModalBody, [ option ]);
        });

        const passengersTableBody = DOM.elid("passengers-table-body");
        contract.passengers.forEach((passenger, index) => {
            const tr = DOM.makeElement('tr');
            const indexCol = DOM.th({ scope: 'row' }, (index + 1).toString());
            const addressCol = DOM.td({}, passenger);

            DOM.appendArray(tr, [ indexCol, addressCol ]);

            passengersTableBody.appendChild(tr);
        });

        const flightsTableBody = DOM.elid("flights-table-body");
        contract.flights.forEach((flight, index) => {
            console.log('Flight element:', flight);

            const tr = DOM.makeElement('tr');
            const indexCol = DOM.th({ scope: 'row' }, (index + 1).toString());
            const nameCol = DOM.td({}, flight.flight);
            const airlineCol = DOM.td({}, flight.airline.toString());

            const date = new Date(parseInt(flight.timestamp));
            const timestampCol = DOM.td({}, date.getDay() + "/" + date.getMonth() + "/" + date.getUTCFullYear());

            DOM.appendArray(tr, [ indexCol, nameCol, airlineCol, timestampCol ]);

            flightsTableBody.appendChild(tr);
        });

        DOM.elid('flights-table-fetch-button').addEventListener('click', () => {
            const modalFooter = DOM.elid("flight-modal-footer");

            let fetchButton = DOM.elid("flight-modal-footer-fetch-button");
            let registerButton = DOM.elid("flight-modal-footer-register-button");

            if (registerButton) {
                DOM.removeElement(modalFooter, registerButton);
            }

            if (!fetchButton) {
                fetchButton = DOM.button({ id: 'flight-modal-footer-fetch-button', type: 'button', className: 'btn btn-primary' }, 'Fetch');
                DOM.appendArray(modalFooter, [ fetchButton ]);
            }
        });

        DOM.elid('flights-table-register-button').addEventListener('click', () => {
            const modalFooter = DOM.elid("flight-modal-footer");

            let registerButton = DOM.elid("flight-modal-footer-register-button");
            let fetchButton = DOM.elid("flight-modal-footer-fetch-button");

            if (fetchButton) {
                DOM.removeElement(modalFooter, fetchButton);
            }

            if (!registerButton) {
                registerButton = DOM.button({ id: 'flight-modal-footer-register-button', type: 'button', className: 'btn btn-primary' }, 'Register');
                registerButton.addEventListener('click', () => {
                    const airlineAddress = DOM.elid('flight-modal-body-input-airline').value;
                    const flightCode = DOM.elid('flight-modal-body-input-code').value;
                    const timestamp = DOM.elid('flight-modal-body-input-date').value;

                    contract.registerFlight(airlineAddress, flightCode, Date.parse(timestamp), () => window.location.reload());
                });

                DOM.appendArray(modalFooter, [ registerButton ]);
            }
        });

        const fetchAirlinesButton = DOM.elid("flights-table-fetch-airline-button");
        fetchAirlinesButton.addEventListener('click', () => {
            contract.fetchAllAirlines();
        });

        const fetchFlightsButton = DOM.elid("flights-table-fetch-flights-button");
        fetchFlightsButton.addEventListener('click', () => {
            contract.fetchAllFlights();
        });

        // User-submitted transaction
        // DOM.elid('submit-oracle').addEventListener('click', () => {
        //     let flight = DOM.elid('flight-number').value;
        //     // Write transaction
        //     contract.fetchFlightStatus(flight, (error, result) => {
        //         display('Oracles', 'Trigger oracles', [ { label: 'Fetch Flight Status', error: error, value: result.flight + ' ' + result.timestamp} ]);
        //     });
        // })
        //
        // DOM.elid('submit-oracle')
    
    });
})();





