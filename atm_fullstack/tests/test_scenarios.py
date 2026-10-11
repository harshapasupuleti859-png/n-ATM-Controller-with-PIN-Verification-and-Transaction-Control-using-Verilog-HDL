"""
Runs the same scenarios as the README table against whichever backend is available.
   python tests/test_scenarios.py            (auto: Verilog if installed, else mock)
   python tests/test_scenarios.py --mock
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import server

mode = "mock" if "--mock" in sys.argv else "auto"
backend = server.make_backend(mode)
print("Backend:", backend.name)
IDLE, PIN, ACC, MENU, BAL, OK, INS, LOCK = range(8)
C = lambda cmd, a=0, b=0: {"cmd": cmd, "a": a, "b": b}
good_login = [C("CARD"), C("PIN", 0x1234), C("ACC", 0)]
fails = 0

def check(name, history, **expect):
    global fails
    rows, _ = backend.run(history)
    last = rows[-1]
    bad = {k: (last[k], v) for k, v in expect.items() if last[k] != v}
    print(("PASS " if not bad else "FAIL ") + name, "" if not bad else bad)
    fails += bool(bad)

check("Correct PIN",            [C("CARD"), C("PIN", 0x1234)], state=ACC, auth=1)
check("Incorrect PIN",          [C("CARD"), C("PIN", 0x1111)], state=PIN, err=1, attempts=1)
check("3 wrong PINs lock",      [C("CARD")] + [C("PIN", 0x1111)] * 3, state=LOCK, locked=1)
check("Account selection",      good_login, state=MENU, balance=1000)
check("Balance inquiry",        good_login + [C("TXN", 0)], state=BAL, balance=1000)
check("Withdraw 200 from 1000", good_login + [C("TXN", 1, 200)], state=OK, balance=800, ok=1)
check("Deposit 500",            good_login + [C("TXN", 2, 500)], state=OK, balance=1500, ok=1)
check("Withdraw > balance",     good_login + [C("TXN", 1, 5000)], state=INS, insuf=1, balance=1000)
check("Back to menu",           good_login + [C("TXN", 1, 200), C("BACK")], state=MENU, balance=800)
check("Eject card",             good_login + [C("CANCEL")], state=IDLE, auth=0)
print("\nAll tests passed." if not fails else "\n%d test(s) FAILED." % fails)
sys.exit(1 if fails else 0)
