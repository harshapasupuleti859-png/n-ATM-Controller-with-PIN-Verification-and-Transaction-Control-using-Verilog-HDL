# ATM Controller with PIN Verification and Transaction Control using Verilog HDL

This repository contains a modular Verilog-based ATM controller and a full-stack web banking demo that connects the hardware simulation to a browser UI. The project combines digital design, HDL verification, and a Python web application to demonstrate a realistic ATM workflow.

## Overview

The core hardware design is implemented in the `ATM_Controller/` directory and models a complete ATM state machine with:

- PIN verification
- account selection
- balance inquiry
- withdrawal and deposit logic
- insufficient-funds handling
- account lockout after repeated wrong PIN attempts
- FSM-based transaction flow

In addition to the RTL design, the repository includes a Python-based full-stack application in `atm_fullstack/` that:

- serves a banking portal and ATM simulator UI
- stores accounts and transaction history in SQLite
- calls the Verilog simulation through Icarus Verilog / `vvp`
- exposes REST APIs for login, registration, balance queries, and transactions
- supports local execution and deployment via Docker, Render, and Vercel

---

## Features

### Hardware / Verilog Features

- 4-digit PIN authentication
- invalid PIN detection
- lock-after-3-attempts logic
- account selection support
- balance inquiry
- withdrawal and deposit operations
- insufficient-funds detection
- modular RTL architecture
- FSM-driven transaction processing
- testbench validation for functional simulation

### Software / Full-Stack Features

- browser-based banking dashboard
- virtual ATM hardware console
- live simulation status and state reporting
- SQLite-backed accounts and transaction ledger
- REST API endpoints for account operations
- Docker-ready deployment
- cloud deployment configuration via Render and Vercel

---

## Repository Structure

```text
.
├── ATM_Controller/
│   ├── account_manager.v
│   ├── atm_fsm.v
│   ├── atm_top.v
│   ├── balance_manager.v
│   ├── pin_verification.v
│   ├── tb_atm_top.v
│   └── transaction_controller.v
├── atm_fullstack/
│   ├── app.py
│   ├── config.json
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── README.md
│   ├── run_mac_linux.sh
│   ├── run_windows.bat
│   ├── rtl/
│   ├── sim/
│   ├── server.py
│   ├── tests/
│   └── web/
├── api/
│   └── index.py
├── public/
│   ├── bank.html
│   └── index.html
├── Dockerfile
├── render.yaml
├── vercel.json
├── README.md
├── .gitignore
└── .dockerignore
```

---

## Hardware Design Modules

The RTL implementation is organized into the following modules:

### `pin_verification.v`
Handles the PIN-entry process, comparison against a stored PIN, invalid-attempt counting, and lockout state.

### `account_manager.v`
Controls account selection and validates the chosen account before continuing the session.

### `balance_manager.v`
Tracks the current balance and performs withdrawal and deposit updates while checking for insufficient funds.

### `transaction_controller.v`
Routes user transactions such as balance inquiry, withdrawal, and deposit to the appropriate control logic.

### `atm_fsm.v`
Implements the finite-state machine that orchestrates authentication, account selection, transaction execution, and error states.

### `atm_top.v`
Integrates the controller modules into one ATM system.

### `tb_atm_top.v`
Contains the functional verification testbench used to simulate and validate the ATM controller.

---

## Full-Stack Web App

The `atm_fullstack/` folder contains a Python application that serves a full-stack ATM banking experience.

### Available interfaces

- `/` or `/bank` -> banking portal
- `/atm` -> hardware ATM simulator console
- REST endpoints for login, registration, transactions, and session state

### Demo accounts

- Card: `1001` / PIN: `1234` / Balance: `$1000`
- Card: `1002` / PIN: `4321` / Balance: `$2500`

### Start locally

```bash
cd atm_fullstack
python3 app.py
```

Then open:

- `http://localhost:8000/` for the bank interface
- `http://localhost:8000/atm` for the ATM simulator

### Run tests

```bash
cd atm_fullstack
python3 tests/test_scenarios.py
```

---

## Deployment

This repository includes cloud and container deployment support:

### Docker

The root `Dockerfile` and `atm_fullstack/Dockerfile` package the application for running on a container platform.

```bash
docker build -t atm-controller-bank .
docker run -p 8000:8000 atm-controller-bank
```

Or from the full-stack directory:

```bash
cd atm_fullstack
docker compose up -d --build
```

### Render

`render.yaml` defines a web service for deployment on Render.

### Vercel

`vercel.json` rewrites API and page routes for Vercel hosting.

The `api/index.py` file configures the serverless entry point for the banking backend.

---

## Simulation and Verification

The design supports both HDL-level verification and integrated backend testing.

- `ATM_Controller/tb_atm_top.v` validates the Verilog logic through simulation
- `atm_fullstack/tests/test_scenarios.py` checks the backend and transaction flow
- Icarus Verilog is used to execute the hardware model when available
- the application can also fall back to a Python mock mode for demos and testing

---

## Typical ATM Flow

```text
IDLE
  -> PIN ENTRY
  -> ACCOUNT SELECTION
  -> TRANSACTION MENU
      -> BALANCE INQUIRY
      -> WITHDRAWAL
      -> DEPOSIT
  -> TRANSACTION COMPLETE
  -> INVALID PIN / INSUFFICIENT FUNDS / LOCKED STATE
```

---

## Technology Stack

- Verilog HDL
- Icarus Verilog
- Python 3
- SQLite
- Flask-like lightweight HTTP server patterns
- Docker
- HTML/CSS/JavaScript UI

---

## Notes

This project demonstrates both digital design and integration engineering:

- designing a real hardware ATM controller in Verilog
- verifying control behavior with a testbench
- exposing simulation results to a web interface
- combining hardware logic with software account and transaction management

It is suitable for FPGA-oriented learning, hardware design practice, and full-stack demonstration of embedded logic using a web front end.

---

## License

This project is provided for educational and demonstration purposes.
