#!/usr/bin/env python3
"""Local-only operational dashboard for LeoDigi CyberPanel Toolkit."""
from __future__ import annotations
import hashlib, hmac, os, secrets, subprocess, time
from pathlib import Path
from fastapi import FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from starlette.middleware.sessions import SessionMiddleware

app = FastAPI(docs_url=None, redoc_url=None)
app.add_middleware(SessionMiddleware, secret_key=os.environ.get("CPT_DASHBOARD_SECRET", secrets.token_hex(32)), https_only=True, same_site="strict")
CLI = "/usr/local/sbin/toolkitctl"
ALLOWED = {
    "health": ["health"], "doctor": ["doctor"], "backup-list": ["backup", "list"],
    "backup-check": ["backup", "check"], "wp-list": ["wp", "list"],
    "mail-status": ["mail", "status"], "ssl-check": ["ssl", "check"],
    "monitoring": ["monitoring", "status"], "firewall": ["firewall", "status"],
}

STYLE = """body{font:15px system-ui;background:#0b1220;color:#e5e7eb;margin:0}main{max-width:1100px;margin:auto;padding:28px}.card{background:#151f32;border:1px solid #26344f;border-radius:12px;padding:18px;margin:14px 0}button,input{padding:10px;border-radius:7px;border:1px solid #475569}button{background:#2563eb;color:white;cursor:pointer}pre{white-space:pre-wrap;background:#07101f;padding:14px;border-radius:8px;overflow:auto}a{color:#93c5fd}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:12px}"""

def authenticated(request: Request) -> bool:
    return request.session.get("auth") is True

@app.get("/login", response_class=HTMLResponse)
def login_page():
    return f"<style>{STYLE}</style><main><div class=card><h1>LeoDigi CyberPanel Toolkit</h1><p>leodigi.dev</p><form method=post><input name=user placeholder=User><input type=password name=password placeholder=Password><button>Login</button></form></div></main>"

@app.post("/login")
def login(request: Request, user: str = Form(...), password: str = Form(...)):
    expected_user=os.environ.get("CPT_DASHBOARD_USER", "admin")
    expected_hash=os.environ.get("CPT_DASHBOARD_PASSWORD_SHA256", "")
    actual=hashlib.sha256(password.encode()).hexdigest()
    if not (hmac.compare_digest(user, expected_user) and hmac.compare_digest(actual, expected_hash)):
        time.sleep(1); raise HTTPException(401, "Invalid credentials")
    request.session["auth"]=True
    return RedirectResponse("/", 303)

@app.get("/", response_class=HTMLResponse)
def home(request: Request):
    if not authenticated(request): return RedirectResponse("/login", 303)
    buttons="".join(f"<form method=post action=/run/{key}><button>{key}</button></form>" for key in ALLOWED)
    return f"<style>{STYLE}</style><main><h1>LeoDigi CyberPanel Toolkit</h1><p><a href='https://leodigi.dev' target='_blank' rel='noopener'>leodigi.dev</a></p><div class='card grid'>{buttons}</div><div class=card><p>Read-only actions are exposed here. Destructive operations remain CLI-only and require confirmation.</p></div></main>"

@app.post("/run/{action}", response_class=HTMLResponse)
def run_action(request: Request, action: str):
    if not authenticated(request): return RedirectResponse("/login", 303)
    if action not in ALLOWED: raise HTTPException(404)
    result=subprocess.run([CLI, *ALLOWED[action]], text=True, capture_output=True, timeout=120, env={**os.environ, "LC_ALL":"C"})
    output=(result.stdout+"\n"+result.stderr)[-60000:]
    import html
    return f"<style>{STYLE}</style><main><a href='/'>Back</a><div class=card><h2>{html.escape(action)}</h2><pre>{html.escape(output)}</pre></div></main>"

@app.post("/logout")
def logout(request: Request):
    request.session.clear(); return RedirectResponse("/login", 303)
