import os
import sys

# Ensure atm_fullstack is in the Python search path
API_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(API_DIR)
FULLSTACK_DIR = os.path.join(REPO_ROOT, "atm_fullstack")
if FULLSTACK_DIR not in sys.path:
    sys.path.insert(0, FULLSTACK_DIR)

# Force Vercel flag for /tmp/bank.db
os.environ["VERCEL"] = "1"

import app as A

# Initialize simulation model and SQLite database on /tmp
A.ensure_sim(mode="mock")

class handler(A.H):
    """Vercel serverless function request handler"""
    pass
