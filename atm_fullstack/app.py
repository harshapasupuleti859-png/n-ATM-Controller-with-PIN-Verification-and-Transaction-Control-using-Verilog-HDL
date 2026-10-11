#!/usr/bin/env python3
"""Full-stack ATM bank: web UI + REST API + SQLite database + Verilog controller.
Every login / transaction is decided by the Verilog design (via server.py backends).
Run:  python app.py [--mock] [--port PORT]   ->  http://localhost:8000
"""
import argparse
import json
import mimetypes
import os
import secrets
import sqlite3
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import server as S

DB = os.path.join(S.ROOT, "bank.db")
SESSIONS = {}                      # token -> card number
SIM = None                         # Verilog (or mock) backend
SESSION = None                     # Hardware interactive session
SIM_LOCK = threading.Lock()        # Prevent race conditions in sim/session.cmd


def db():
    c = sqlite3.connect(DB, timeout=10.0)
    c.row_factory = sqlite3.Row
    return c


def init_db():
    with db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS accounts(
            card TEXT PRIMARY KEY,
            name TEXT,
            pin TEXT,
            balance INTEGER,
            attempts INTEGER DEFAULT 0,
            locked INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS tx(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            card TEXT,
            kind TEXT,
            amount INTEGER,
            result TEXT,
            balance_after INTEGER,
            ts TEXT
        );
        """)
        if not c.execute("SELECT 1 FROM accounts").fetchone():
            c.executemany(
                "INSERT INTO accounts(card, name, pin, balance) VALUES(?,?,?,?)",
                [("1001", "Asha", "1234", 1000), ("1002", "Ravi", "4321", 2500)]
            )


C = lambda cmd, a=0, b=0: {"cmd": cmd, "a": a, "b": b}


def simulate(acc, extra):
    """Replay: load account into hardware, insert card, enter PIN, then `extra` commands."""
    pin = int(acc["pin"], 16)
    h = [C("LOAD", pin, acc["balance"]), C("CARD")]
    h += [C("PIN", pin ^ 1)] * acc["attempts"]       # earlier wrong attempts (hardware counts them)
    with SIM_LOCK:
        return SIM.run(h + extra)


def login(card, pin):
    card = str(card).strip()
    pin = str(pin).strip()
    with db() as c:
        a = c.execute("SELECT * FROM accounts WHERE card=?", (card,)).fetchone()
        if not a:
            return 401, {"error": f"Unknown card number '{card}'. Use demo cards 1001 or 1002, or open an account."}
        if a["locked"]:
            return 403, {"error": "Account is LOCKED after 3 incorrect PIN attempts. Use 'Reset Demo Accounts' or contact bank admin."}
        if not (len(pin) == 4 and pin.isdigit()):
            return 400, {"error": "PIN must be exactly 4 numeric digits."}

        try:
            rows, raw = simulate(a, [C("PIN", int(pin, 16))])
        except Exception as e:
            return 500, {"error": f"Hardware simulation error: {e}"}

        st = rows[-1]
        if st["state"] == 2:                          # ACCOUNT_SELECT -> PIN accepted by hardware
            c.execute("UPDATE accounts SET attempts=0, locked=0 WHERE card=?", (card,))
            tok = secrets.token_hex(16)
            SESSIONS[tok] = card
            return 200, {"token": tok, "sim": raw, "name": a["name"], "card": card}

        # Failed attempt
        n = a["attempts"] + 1
        is_locked = bool(st.get("locked") or n >= 3)
        c.execute("UPDATE accounts SET attempts=?, locked=? WHERE card=?", (n, int(is_locked), card))
        remaining = max(0, 3 - n)
        err_msg = "Account LOCKED by hardware after 3 failed attempts." if is_locked else f"Incorrect PIN ({remaining} attempt(s) remaining)."
        return (403 if is_locked else 401), {"error": err_msg, "sim": raw, "attempts_left": remaining, "locked": is_locked}


def transact(card, kind, amount):
    if kind not in ("balance", "withdraw", "deposit"):
        return 400, {"error": "Invalid transaction type"}
    t = {"balance": 0, "withdraw": 1, "deposit": 2}[kind]

    with db() as c:
        a = c.execute("SELECT * FROM accounts WHERE card=?", (card,)).fetchone()
        if not a:
            return 404, {"error": "Account not found"}
        if a["locked"]:
            return 403, {"error": "Account is locked"}

        if kind == "deposit" and a["balance"] + amount > 65535:
            return 400, {"error": "Deposit exceeds 16-bit hardware balance limit (65535 max)"}

        try:
            with SIM_LOCK:
                rows, raw = SIM.run([
                    C("LOAD", int(a["pin"], 16), a["balance"]),
                    C("CARD"),
                    C("PIN", int(a["pin"], 16)),
                    C("ACC", 0),
                    C("TXN", t, amount)
                ])
        except Exception as e:
            return 500, {"error": f"Hardware simulation error: {e}"}

        st = rows[-1]
        result = {4: "BALANCE", 5: "OK", 6: "INSUFFICIENT"}.get(st.get("state"), "ERROR")
        new_balance = st.get("balance", a["balance"])

        c.execute("UPDATE accounts SET balance=? WHERE card=?", (new_balance, card))
        c.execute(
            "INSERT INTO tx(card, kind, amount, result, balance_after, ts) VALUES(?,?,?,?,?,?)",
            (card, kind, amount, result, new_balance, time.strftime("%Y-%m-%d %H:%M:%S"))
        )
        return 200, {
            "result": result,
            "balance": new_balance,
            "sim": raw,
            "state": st.get("state"),
            "state_name": S.CONFIG.get("state_names", {}).get(str(st.get("state")), "STATE_" + str(st.get("state")))
        }


def me(card):
    if not card:
        return 401, {"error": "Login required"}
    with db() as c:
        a = c.execute("SELECT name, card, balance, locked, attempts FROM accounts WHERE card=?", (card,)).fetchone()
        if not a:
            return 404, {"error": "Account not found"}
        h = c.execute("SELECT id, kind, amount, result, balance_after, ts FROM tx WHERE card=? ORDER BY id DESC LIMIT 30", (card,)).fetchall()
        return 200, {**dict(a), "history": [dict(x) for x in h]}


def register(name, pin, initial_bal=1000):
    name = (name or "").strip()
    pin = (pin or "").strip()
    if not name:
        return 400, {"error": "Please provide a valid account holder name"}
    if not (len(pin) == 4 and pin.isdigit()):
        return 400, {"error": "PIN must be exactly 4 digits (e.g. 1234)"}

    with db() as c:
        row = c.execute("SELECT MAX(CAST(card AS INTEGER)) FROM accounts").fetchone()
        next_card = (row[0] + 1) if (row and row[0] is not None) else 1001
        card = str(max(1001, next_card))
        initial_bal = max(0, min(65535, int(initial_bal or 0)))
        c.execute("INSERT INTO accounts(card, name, pin, balance, attempts, locked) VALUES(?,?,?,?,0,0)",
                  (card, name[:40], pin, initial_bal))
        if initial_bal > 0:
            c.execute("INSERT INTO tx(card, kind, amount, result, balance_after, ts) VALUES(?,?,?,?,?,?)",
                      (card, "deposit", initial_bal, "OK", initial_bal, time.strftime("%Y-%m-%d %H:%M:%S")))
        return 200, {"card": card, "name": name, "balance": initial_bal, "message": f"Account opened successfully! Your card number is {card}."}


def reset_demo_account(card=None):
    with db() as c:
        if card:
            c.execute("UPDATE accounts SET attempts=0, locked=0 WHERE card=?", (card,))
        else:
            c.execute("UPDATE accounts SET attempts=0, locked=0, balance=1000 WHERE card='1001'")
            c.execute("UPDATE accounts SET attempts=0, locked=0, balance=2500 WHERE card='1002'")
        return 200, {"message": "Demo accounts unlocked and restored."}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def out(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            b = json.dumps(body).encode("utf-8")
        elif isinstance(body, str):
            b = body.encode("utf-8")
        else:
            b = body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(b)

    def do_HEAD(self):
        self.do_GET()

    def card(self):
        auth = self.headers.get("Authorization", "")
        token = auth.replace("Bearer ", "").strip()
        return SESSIONS.get(token)

    def do_GET(self):
        path = self.path.split("?")[0]
        # REST APIs
        if path == "/api/me":
            return self.out(*me(self.card()))
        if path == "/api/config":
            return self.out(200, {
                "state_names": S.CONFIG["state_names"],
                "backend": SIM.name if SIM else "unknown"
            })
        if path == "/api/state":
            global SESSION
            if SESSION is None and SIM is not None:
                SESSION = S.Session(SIM)
            return self.out(200, SESSION.execute() if SESSION else {"ok": False, "error": "No simulation active"})
        if path == "/api/vcd":
            f = os.path.join(S.SIM_DIR, "session.vcd")
            if os.path.exists(f):
                with open(f, "rb") as fh:
                    data = fh.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Disposition", "attachment; filename=session.vcd")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            return self.out(404, {"error": "No waveform file found. Perform an action in Verilog mode first."})

        # Web page routes
        if path in ("/", "/bank", "/bank.html"):
            bank_file = os.path.join(S.WEB_DIR, "bank.html")
            if os.path.isfile(bank_file):
                with open(bank_file, "rb") as fh:
                    return self.out(200, fh.read(), "text/html; charset=utf-8")
        if path in ("/atm", "/index.html", "/simulator"):
            index_file = os.path.join(S.WEB_DIR, "index.html")
            if os.path.isfile(index_file):
                with open(index_file, "rb") as fh:
                    return self.out(200, fh.read(), "text/html; charset=utf-8")

        # Static assets in web/
        asset = os.path.normpath(os.path.join(S.WEB_DIR, path.lstrip("/")))
        if asset.startswith(S.WEB_DIR) and os.path.isfile(asset):
            mime = mimetypes.guess_type(asset)[0] or "application/octet-stream"
            with open(asset, "rb") as fh:
                return self.out(200, fh.read(), mime)

        self.out(404, {"error": f"Endpoint or file '{path}' not found"})

    def do_POST(self):
        content_len = self.headers.get("Content-Length")
        raw_body = self.rfile.read(int(content_len)) if content_len else b"{}"
        try:
            d = json.loads(raw_body.decode("utf-8") or "{}")
        except Exception:
            return self.out(400, {"error": "Malformed JSON payload"})

        try:
            if self.path == "/api/login":
                return self.out(*login(d.get("card", ""), d.get("pin", "")))

            if self.path == "/api/register":
                return self.out(*register(d.get("name", ""), d.get("pin", ""), d.get("initial_bal", 1000)))

            if self.path == "/api/reset-account":
                return self.out(*reset_demo_account(d.get("card")))

            if self.path == "/api/logout":
                token = self.headers.get("Authorization", "").replace("Bearer ", "").strip()
                SESSIONS.pop(token, None)
                return self.out(200, {"ok": True, "message": "Logged out successfully"})

            if self.path == "/api/txn":
                c = self.card()
                if not c:
                    return self.out(401, {"error": "Authentication required. Please sign in."})
                try:
                    amt = int(d.get("amount", 0))
                except (ValueError, TypeError):
                    return self.out(400, {"error": "Amount must be a valid non-negative integer"})
                kind = str(d.get("type", "")).lower()
                if kind not in ("balance", "withdraw", "deposit") or not (0 <= amt <= 65535):
                    return self.out(400, {"error": "Invalid transaction type or amount out of bounds (0..65535)"})
                if kind != "balance" and amt <= 0:
                    return self.out(400, {"error": "Transaction amount must be greater than zero"})
                return self.out(*transact(c, kind, amt))

            if self.path == "/api/cmd":
                global SESSION
                if SESSION is None and SIM is not None:
                    SESSION = S.Session(SIM)
                cmd = str(d.get("cmd", "")).upper()
                if cmd not in ("RESET", "LOAD", "CARD", "PIN", "ACC", "TXN", "BACK", "CANCEL"):
                    return self.out(400, {"ok": False, "error": f"Invalid command '{cmd}'"})
                try:
                    a = int(d.get("a", 0))
                    b = int(d.get("b", 0))
                except (ValueError, TypeError):
                    a = 0
                    b = 0
                return self.out(200, SESSION.execute(cmd, a, b))

        except Exception as e:
            return self.out(500, {"error": str(e)})

        self.out(404, {"error": f"Endpoint '{self.path}' not found"})


def main():
    global SIM, SESSION
    ap = argparse.ArgumentParser(description="Full-stack ATM Bank (Verilog + Python + SQLite)")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--mock", action="store_true", help="Force Python behavioral model")
    g.add_argument("--verilog", action="store_true", help="Force Icarus Verilog mode")
    default_port = int(os.environ.get("PORT", S.CONFIG.get("port", 8000)))
    default_host = os.environ.get("HOST", "0.0.0.0")
    ap.add_argument("--host", default=default_host, help=f"Host to bind (default: {default_host})")
    ap.add_argument("--port", type=int, default=default_port, help=f"Port to listen on (default: {default_port})")
    args = ap.parse_args()

    mode = "mock" if args.mock else "verilog" if args.verilog else "auto"
    SIM = S.make_backend(mode)
    SESSION = S.Session(SIM)
    init_db()

    port = args.port
    host = args.host
    display_host = "localhost" if host in ("0.0.0.0", "127.0.0.1") else host
    print("=" * 65)
    print(f"  🏧 FULL-STACK ATM BANK CONTROLLER ({SIM.name.upper()} BACKEND)")
    print("=" * 65)
    print(f"  • Web Bank Portal:        http://{display_host}:{port}/")
    print(f"  • Hardware ATM Console:   http://{display_host}:{port}/atm")
    print(f"  • Backend Engine:         {SIM.name.upper()} (Verilog RTL / Mock)")
    print(f"  • SQLite Database:        {DB}")
    print("=" * 65)
    print("Press Ctrl+C to stop the server.\n")

    srv = ThreadingHTTPServer((host, port), H)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping ATM server.")


if __name__ == "__main__":
    main()
