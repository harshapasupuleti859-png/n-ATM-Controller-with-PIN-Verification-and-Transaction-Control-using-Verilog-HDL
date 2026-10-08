# ATM Controller using Verilog HDL

A modular **ATM Controller designed using Verilog HDL**, implementing PIN authentication, account selection, balance management, withdrawal, deposit, insufficient-funds handling, transaction control, and finite state machine (FSM) based system control.

The project is designed with a **modular RTL architecture**, making it easier to simulate, verify, debug, and extend toward FPGA-based implementation.

---

## 📌 Project Overview

This project models the control logic of an Automated Teller Machine (ATM) using **Verilog HDL**.

The design separates major ATM operations into independent RTL modules such as:

* PIN verification
* Account management
* Balance management
* Transaction control
* ATM state-machine control
* Top-level system integration

The modular approach improves **design readability, reusability, verification, and scalability**.

---

## ✨ Features

* 🔐 4-digit PIN authentication
* 🚫 Invalid PIN detection
* 🔒 Account lock after multiple incorrect PIN attempts
* 👤 Account selection
* 💰 Balance inquiry
* 💵 Cash withdrawal
* 💳 Deposit functionality
* ⚠️ Insufficient funds detection
* 🔄 Transaction control
* 🧠 FSM-based ATM operation
* 🧩 Modular RTL architecture
* 🧪 Verilog testbench for functional verification
* 📈 Designed with future FPGA implementation in mind

---

## 🏗️ System Architecture

```text
                    +----------------------+
                    |      ATM Top         |
                    |     atm_top.v        |
                    +----------+-----------+
                               |
        +----------------------+----------------------+
        |                      |                      |
        v                      v                      v
+---------------+     +----------------+     +---------------------+
| PIN           |     | Account        |     | Transaction         |
| Verification  |     | Manager        |     | Controller          |
+---------------+     +----------------+     +---------------------+
        |                      |                      |
        +----------------------+----------------------+
                               |
                               v
                    +----------------------+
                    |  Balance Manager     |
                    | balance_manager.v    |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |      ATM FSM         |
                    |     atm_fsm.v        |
                    +----------------------+
```

---

## 📂 Project Structure

```text
ATM_Controller/
│
├── rtl/
│   ├── pin_verification.v
│   ├── account_manager.v
│   ├── balance_manager.v
│   ├── transaction_controller.v
│   ├── atm_fsm.v
│   └── atm_top.v
│
└── tb/
    └── tb_atm_top.v
```

---

## 🔧 Module Description

### 1. `pin_verification.v`

Handles user PIN authentication.

**Responsibilities:**

* Accepts PIN digits sequentially
* Compares the entered PIN with the stored PIN
* Generates valid/invalid PIN status
* Tracks incorrect attempts
* Locks the account after the configured number of failed attempts

---

### 2. `account_manager.v`

Handles account-selection logic after successful authentication.

**Responsibilities:**

* Receives account-selection input
* Confirms account selection
* Provides account-selection status to the ATM controller

---

### 3. `balance_manager.v`

Manages the account balance and transaction amounts.

**Responsibilities:**

* Stores the current account balance
* Processes withdrawals
* Processes deposits
* Detects insufficient funds
* Generates transaction-success status

Example:

```text
Initial Balance = 1000

Withdrawal = 200

Final Balance = 800
```

---

### 4. `transaction_controller.v`

Controls the user's selected transaction.

Supported operations include:

```text
00 → Balance Inquiry
01 → Withdrawal
10 → Deposit
```

The module generates the appropriate transaction request for the selected operation.

---

### 5. `atm_fsm.v`

Implements the main **Finite State Machine (FSM)** of the ATM.

Typical system states include:

```text
IDLE
  ↓
PIN_ENTRY
  ↓
ACCOUNT_SELECTION
  ↓
MENU
  ├── BALANCE
  ├── WITHDRAW
  └── DEPOSIT
  ↓
TRANSACTION COMPLETE
```

Additional states handle:

```text
INSUFFICIENT FUNDS
ACCOUNT LOCKED
```

---

### 6. `atm_top.v`

Acts as the top-level integration module.

It connects:

* PIN verification
* Account management
* Balance management
* Transaction controller
* ATM FSM

into a single ATM system.

---

### 7. `tb_atm_top.v`

Provides functional verification of the ATM controller.

The testbench generates:

* Clock
* Reset
* PIN input
* Account selection
* Transaction selection
* Withdrawal amount
* Deposit amount

and verifies the resulting outputs.

---

## 🔄 ATM Operation Flow

```text
        +-------+
        | IDLE  |
        +---+---+
            |
            v
     +-------------+
     | Enter PIN   |
     +------+------+
            |
       +----+----+
       |         |
     Valid     Invalid
       |         |
       v         v
+-------------+  Retry
| Select      |
| Account     |
+------+------+
       |
       v
+-------------+
| Transaction |
| Menu        |
+------+------+ 
       |
   +---+---+---+
   |       |   |
   v       v   v
Balance Withdraw Deposit
   |       |   |
   +---+---+---+
       |
       v
+-------------+
| Transaction |
| Complete    |
+-------------+
```

---

## 🧪 Verification

The testbench verifies major functional scenarios including:

| Test Case                    | Expected Result                     |
| ---------------------------- | ----------------------------------- |
| Correct PIN                  | Authentication successful           |
| Incorrect PIN                | Invalid PIN detected                |
| Multiple incorrect PINs      | Account locked                      |
| Account selection            | Account selected                    |
| Balance inquiry              | Current balance displayed           |
| Valid withdrawal             | Balance reduced                     |
| Deposit                      | Balance increased                   |
| Withdrawal exceeding balance | Insufficient funds                  |
| Transaction completion       | System returns to appropriate state |

---

## 🛠️ Tools & Technologies

* **Verilog HDL**
* **RTL Design**
* **Finite State Machines**
* **Digital Logic Design**
* **Functional Verification**
* **EDA Playground**
* **Icarus Verilog**
* **VS Code**

---

## 🎯 Design Concepts Demonstrated

This project demonstrates practical understanding of:

* RTL design methodology
* Modular hardware design
* Sequential and combinational logic
* Finite State Machines
* Registers and counters
* Control-path design
* Data-path control
* Input validation
* Error handling
* Hardware-oriented verification
* Testbench development

---

## 🚀 Future Enhancements

The project can be extended toward a more complete FPGA-based ATM system.

### Hardware-Level Enhancements

* FPGA implementation
* Matrix keypad interface
* LCD/OLED display
* Seven-segment display
* Push-button interface
* LED status indicators
* Buzzer
* UART communication

### Security Enhancements

* Configurable PIN storage
* PIN change functionality
* Improved authentication logic
* Timeout mechanism
* Transaction authorization
* Multiple-account support

### Software-Level Enhancements

* Account database
* Transaction history
* Account creation
* User management
* Admin interface
* Balance management software
* Transaction reports

---

## 📈 Future Architecture

The long-term goal is to extend the project into a complete hardware-software ATM system:

```text
                 ATM SYSTEM
                     |
          +----------+----------+
          |                     |
          v                     v
   FPGA / Hardware       Software Layer
          |                     |
     Keypad/LCD             Accounts
     Controller             Database
     FSM                    Transactions
     Security               History
     Balance                Reports
          |                     |
          +----------+----------+
                     |
                     v
              Complete ATM
                 System
```

---

## 📚 Learning Outcomes

Through this project, the following concepts are practiced:

1.
