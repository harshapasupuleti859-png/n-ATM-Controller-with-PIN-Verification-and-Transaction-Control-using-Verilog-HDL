#!/usr/bin/env python3
"""
ATM Controller - software front-end for the Verilog design.

  python server.py            -> uses Icarus Verilog (iverilog + vvp) if found,
                                 otherwise falls back to a Python model (mock)
  python server.py --mock     -> force the Python model (no Verilog needed)
  python server.py --verilog  -> force Icarus Verilog (error if not installed)

Open http://localhost:8000 in a browser.
No third-party Python packages are required.
"""
import argparse, glob, json, mimetypes, os, shutil, subprocess, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
SIM_DIR = os.path.join(ROOT, "sim")
WEB_DIR = os.path.join(ROOT, "web")

with open(os.path.join(ROOT, "config.json")) as f:
    CONFIG = json.load(f)

FIELDS = ["idx", "state", "auth", "locked", "err", "attempts", "balance", "ok", "insuf"]


def parse_line(line):
    d = {}
    for part in line.strip().split("|")[1:]:
        if "=" in part:
            k, v = part.split("=", 1)
            try:
                d[k] = int(v)
            except ValueError:
                d[k] = v          # e.g. 'x' / 'z' values from an unknown signal
    return d


def resolve_tool(name):
    t = shutil.which(name)
    if t:
        return t
    for p in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]:
        candidate = os.path.join(p, name)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


# --------------------------------------------------------------------------
# Backend 1: real Verilog through Icarus Verilog
# --------------------------------------------------------------------------
class VerilogBackend:
    name = "verilog"

    def __init__(self):
        self.iverilog = resolve_tool(CONFIG["iverilog"])
        self.vvp = resolve_tool(CONFIG["vvp"])
        self._compiled_stamp = None

    @property
    def available(self):
        return bool(self.iverilog and self.vvp)

    def _sources(self):
        files = sorted(glob.glob(os.path.join(ROOT, CONFIG["rtl_glob"])))
        files.append(os.path.join(ROOT, CONFIG["testbench"]))
        return files

    def _compile(self):
        srcs = self._sources()
        stamp = tuple((s, os.path.getmtime(s)) for s in srcs)
        if stamp == self._compiled_stamp:
            return
        cmd = [self.iverilog, "-g2005", "-o", os.path.join(SIM_DIR, "atm.vvp")] + srcs
        p = subprocess.run(cmd, capture_output=True, text=True, cwd=SIM_DIR)
        if p.returncode != 0:
            raise RuntimeError("Verilog compile error:\n" + (p.stderr or p.stdout))
        self._compiled_stamp = stamp

    def run(self, history):
        self._compile()
        with open(os.path.join(SIM_DIR, "session.cmd"), "w") as f:
            for c in history:
                f.write("%s %d %d\n" % (c["cmd"], c["a"], c["b"]))
        p = subprocess.run([self.vvp, "atm.vvp"], capture_output=True, text=True,
                           cwd=SIM_DIR, timeout=30)
        out = p.stdout
        rows = [parse_line(l) for l in out.splitlines() if l.startswith("ATM|")]
        if len(rows) != len(history) + 1:
            raise RuntimeError("Simulation output did not match commands.\n"
                               "--- simulator output ---\n" + out[-1500:] + p.stderr[-500:])
        return rows, out


# --------------------------------------------------------------------------
# Backend 2: Python model of the reference RTL (for demo / testing)
# --------------------------------------------------------------------------
class MockBackend:
    name = "mock"
    available = True
    CORRECT_PIN, MAX_ATTEMPTS = 0x1234, 3

    def run(self, history):
        m = self._fresh()
        rows = [self._row(0, m)]
        for i, c in enumerate(history, 1):
            self._apply(m, c["cmd"], c["a"], c["b"])
            rows.append(self._row(i, m))
        return rows, "(python model - no Verilog simulator used)"

    def _fresh(self):
        return dict(state=0, auth=0, locked=0, err=0, attempts=0, balance=0, ok=0, insuf=0,
                    cur=0, acc=[1000, 2500, 500, 10000])

    def _row(self, i, m):
        r = {k: m[k] for k in FIELDS if k != "idx"}
        r["idx"] = i
        return r

    def _apply(self, m, cmd, a, b):
        s = m["state"]
        if cmd == "RESET":
            m.update(self._fresh())
        elif cmd == "LOAD":
            m["pin"] = a & 0xFFFF; m["acc"][0] = b & 0xFFFF
        elif cmd == "CARD" and s == 0:
            m.update(state=1, err=0, auth=0, ok=0, insuf=0)
        elif cmd == "PIN" and s == 1:
            if (a & 0xFFFF) == m.get("pin", self.CORRECT_PIN):
                m.update(auth=1, err=0, attempts=0, state=2)
            else:
                m["err"] = 1
                if m["attempts"] == self.MAX_ATTEMPTS - 1:
                    m.update(locked=1, state=7)
                m["attempts"] = (m["attempts"] + 1) & 3
        elif cmd == "ACC" and s == 2:
            m["cur"] = a & 3
            m.update(balance=m["acc"][m["cur"]], state=3)
        elif cmd == "TXN" and s == 3:
            t, amt, cur = a & 3, b & 0xFFFF, m["cur"]
            if t == 0:
                m["state"] = 4
            elif t == 1:
                if amt <= m["acc"][cur]:
                    m["acc"][cur] -= amt
                    m.update(balance=m["acc"][cur], ok=1, state=5)
                else:
                    m.update(insuf=1, state=6)
            elif t == 2:
                m["acc"][cur] = (m["acc"][cur] + amt) & 0xFFFF
                m.update(balance=m["acc"][cur], ok=1, state=5)
        elif cmd == "BACK" and s in (4, 5, 6):
            m.update(state=3, ok=0, insuf=0)
        elif cmd == "CANCEL" and s in (1, 2, 3, 4, 5, 6):
            m.update(state=0, auth=0, ok=0, insuf=0, err=0)


# --------------------------------------------------------------------------
# Session handling
# --------------------------------------------------------------------------
class Session:
    def __init__(self, backend):
        self.backend = backend
        self.history = []
        self.lock = threading.Lock()

    def execute(self, cmd=None, a=0, b=0):
        with self.lock:
            if cmd == "RESET":
                self.history = []
            elif cmd:
                self.history.append({"cmd": cmd, "a": int(a), "b": int(b)})
            try:
                rows, raw = self.backend.run(self.history)
            except Exception as e:                      # surface errors in the UI
                if cmd and cmd != "RESET":
                    self.history.pop()
                return {"ok": False, "error": str(e)}
            return {"ok": True, "state": rows[-1], "rows": rows,
                    "history": self.history, "backend": self.backend.name,
                    "raw": raw[-4000:]}


SESSION = None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/config":
            return self._send(200, {"state_names": CONFIG["state_names"],
                                    "backend": SESSION.backend.name})
        if path == "/api/state":
            return self._send(200, SESSION.execute())
        if path == "/api/vcd":
            f = os.path.join(SIM_DIR, "session.vcd")
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
            return self._send(404, {"error": "No waveform yet (needs Verilog mode)."})
        if path in ("/", ""):
            path = "/index.html"
        elif path in ("/bank", "/portal"):
            path = "/bank.html"
        f = os.path.normpath(os.path.join(WEB_DIR, path.lstrip("/")))
        if f.startswith(WEB_DIR) and os.path.isfile(f):
            with open(f, "rb") as fh:
                return self._send(200, fh.read(), mimetypes.guess_type(f)[0] or "text/plain")
        self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/api/cmd":
            n = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(n) or b"{}")
            cmd = str(req.get("cmd", "")).upper()
            if cmd not in ("RESET", "LOAD", "CARD", "PIN", "ACC", "TXN", "BACK", "CANCEL"):
                return self._send(400, {"ok": False, "error": "bad command"})
            return self._send(200, SESSION.execute(cmd, req.get("a", 0), req.get("b", 0)))
        self._send(404, {"error": "not found"})


def make_backend(mode):
    if mode == "mock":
        return MockBackend()
    vb = VerilogBackend()
    if vb.available:
        return vb
    if mode == "verilog":
        sys.exit("ERROR: iverilog/vvp not found. Install Icarus Verilog or run with --mock.")
    print("[!] Icarus Verilog not found -> using the Python model (mock mode).")
    return MockBackend()


def main():
    global SESSION
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--mock", action="store_true")
    g.add_argument("--verilog", action="store_true")
    ap.add_argument("--port", type=int, default=CONFIG.get("port", 8000))
    args = ap.parse_args()
    SESSION = Session(make_backend("mock" if args.mock else "verilog" if args.verilog else "auto"))
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("ATM software running (%s backend)  ->  http://localhost:%d" %
          (SESSION.backend.name, args.port))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
