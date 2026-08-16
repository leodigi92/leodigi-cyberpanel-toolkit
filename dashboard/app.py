#!/usr/bin/env python3
"""LeoDigi CyberPanel Toolkit administrative dashboard."""
from __future__ import annotations

import hashlib
import hmac
import html
import os
import re
import secrets
import shutil
import subprocess
import time
from pathlib import Path

from fastapi import FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from starlette.middleware.sessions import SessionMiddleware

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
app.add_middleware(
    SessionMiddleware,
    secret_key=os.environ.get("CPT_DASHBOARD_SECRET", secrets.token_hex(48)),
    https_only=os.environ.get("DASHBOARD_TLS", "no") == "yes",
    same_site="strict",
    max_age=28800,
)

CLI = "/usr/local/sbin/toolkitctl"
CONFIG_DIR = Path("/etc/leodigi-cyberpanel-toolkit")
STATE_DIR = Path("/var/lib/leodigi-cyberpanel-toolkit")
LOG_DIR = Path("/var/log/leodigi-cyberpanel-toolkit")
SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
NAV = [
    ("overview", "Tổng quan", "⌂"), ("backup", "Backup", "▣"),
    ("wordpress", "WordPress", "W"), ("security", "Bảo mật", "◆"),
    ("mail", "Mail", "✉"), ("ssl", "SSL", "⌁"),
    ("monitoring", "Monitoring", "◉"), ("firewall", "Firewall", "▤"),
    ("logs", "Nhật ký", "≡"),
]

CSS = r"""
:root{--bg:#07101f;--panel:#0e1a2d;--line:#213554;--text:#e8eef8;--muted:#8fa3bf;
--brand:#39d3bb;--blue:#4b8cff;--danger:#ff6074;--warning:#f5b942}*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:14px Inter,system-ui,"Segoe UI",sans-serif}
.layout{min-height:100vh;display:grid;grid-template-columns:250px 1fr}.sidebar{position:fixed;inset:0 auto 0 0;
width:250px;background:#091426;border-right:1px solid var(--line);padding:24px 16px}.brand{display:flex;
align-items:center;gap:11px;padding:0 10px 24px}.logo{width:38px;height:38px;display:grid;place-items:center;
border-radius:11px;background:linear-gradient(135deg,var(--brand),var(--blue));font-size:20px;font-weight:900;color:#06101d}
.brand strong{font-size:16px}.brand small{display:block;color:var(--muted);margin-top:3px}.nav a{display:flex;
align-items:center;gap:12px;color:#aebdd1;text-decoration:none;padding:11px 13px;margin:4px 0;border-radius:9px}
.nav a:hover,.nav a.active{background:#142640;color:#fff}.nav i{font-style:normal;width:22px;text-align:center;
color:var(--brand);font-weight:700}.side-foot{position:absolute;bottom:20px;left:16px;right:16px;border-top:1px solid
var(--line);padding-top:16px;color:var(--muted);font-size:12px}.side-foot a{color:var(--brand)}
.main{grid-column:2;padding:28px 32px 50px;min-width:0}.top{display:flex;justify-content:space-between;
align-items:center;margin-bottom:24px}.top h1{font-size:25px;margin:0 0 5px}.subtitle{color:var(--muted)}
.top-actions{display:flex;gap:8px}.btn,button{border:1px solid #315079;background:#183154;color:#fff;border-radius:8px;
padding:9px 13px;cursor:pointer;font-weight:650}.btn{text-decoration:none;display:inline-block}.btn:hover,button:hover{
filter:brightness(1.15)}.primary{background:linear-gradient(135deg,#2376ee,#31a5ed)!important;border:0!important}
.good{background:#087f70!important;border-color:#0da58f!important}.danger{background:#7f2535!important;border-color:#a83a4d!important}
.grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:16px}.card{background:linear-gradient(145deg,
var(--panel),#101d31);border:1px solid var(--line);border-radius:13px;padding:18px;box-shadow:0 10px 35px #0002}
.span3{grid-column:span 3}.span4{grid-column:span 4}.span6{grid-column:span 6}.span8{grid-column:span 8}
.span12{grid-column:span 12}.metric .label{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.08em}
.metric .value{font-size:27px;font-weight:800;margin:9px 0 5px}.metric .detail{color:var(--muted);font-size:12px}
.bar{height:6px;background:#1d304b;border-radius:9px;overflow:hidden;margin-top:13px}.bar span{display:block;height:100%;
background:linear-gradient(90deg,var(--brand),var(--blue))}.card h2{font-size:16px;margin:0 0 16px}
.status-list{display:grid;grid-template-columns:repeat(2,1fr);gap:9px}.service{display:flex;justify-content:space-between;
align-items:center;background:#0a1628;border:1px solid #1c304d;padding:10px 12px;border-radius:8px}.dot{width:8px;
height:8px;border-radius:50%;display:inline-block;margin-right:8px}.up{background:#26d6a5;box-shadow:0 0 8px #26d6a5}
.down{background:var(--danger)}.badge{font-size:11px;padding:4px 8px;border-radius:20px;background:#17324f;color:#9bc5f8}
.badge.ok{background:#113b35;color:#6ce5c4}.badge.fail{background:#491e2a;color:#ff9aaa}.table{width:100%;
border-collapse:collapse}.table th{text-align:left;color:var(--muted);font-size:11px;text-transform:uppercase;padding:9px;
border-bottom:1px solid var(--line)}.table td{padding:11px 9px;border-bottom:1px solid #1a2b45}.empty{color:var(--muted);
padding:26px;text-align:center;border:1px dashed #315074;border-radius:9px}.forms{display:flex;gap:10px;align-items:end;
flex-wrap:wrap}label{display:block;color:var(--muted);font-size:12px;margin-bottom:6px}input,select{background:#081426;
color:#fff;border:1px solid #2d4668;border-radius:8px;padding:9px 10px;min-width:190px}.notice{padding:12px 14px;
border-radius:9px;background:#112a40;border-left:3px solid var(--blue);margin:0 0 16px;color:#c8d8ea}
.notice.warn{border-color:var(--warning);background:#302817}.terminal{background:#050b14;color:#c8f7e9;
border:1px solid #1f3850;border-radius:10px;padding:16px;white-space:pre-wrap;overflow:auto;max-height:560px;
font:12px/1.6 Consolas,monospace}.quick{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.quick a{
background:#0b192b;border:1px solid #213b5c;border-radius:9px;padding:13px;color:#dbeafe;text-decoration:none}
.quick a:hover{border-color:var(--brand)}.quick small{display:block;color:var(--muted);margin-top:5px}.footer{
color:#637995;text-align:center;margin-top:28px;font-size:12px}
@media(max-width:1000px){.layout{display:block}.sidebar{position:static;width:auto}.nav{display:flex;overflow:auto}
.nav a{white-space:nowrap}.side-foot{display:none}.main{padding:20px}.span3,.span4{grid-column:span 6}}
@media(max-width:650px){.span3,.span4,.span6,.span8{grid-column:span 12}.status-list,.quick{grid-template-columns:1fr}}
"""


def authenticated(request: Request) -> bool:
    return request.session.get("auth") is True


def require_auth(request: Request) -> None:
    if not authenticated(request):
        raise HTTPException(401, "Authentication required")


def csrf(request: Request) -> str:
    token = request.session.get("csrf")
    if not token:
        token = secrets.token_urlsafe(32)
        request.session["csrf"] = token
    return token


def verify_csrf(request: Request, token: str) -> None:
    expected = request.session.get("csrf", "")
    if not expected or not hmac.compare_digest(expected, token):
        raise HTTPException(403, "Invalid CSRF token")


def command(args: list[str], timeout: int = 120) -> tuple[int, str]:
    try:
        result = subprocess.run([CLI, *args], text=True, capture_output=True, timeout=timeout,
                                env={**os.environ, "LC_ALL": "C", "LANG": "C"})
        output = (result.stdout + ("\n" if result.stdout and result.stderr else "") + result.stderr).strip()
        return result.returncode, output[-120000:]
    except subprocess.TimeoutExpired:
        return 124, f"Command timed out after {timeout} seconds"
    except OSError as exc:
        return 127, str(exc)


def valid_name(value: str, label: str) -> str:
    value = value.strip()
    if not SAFE_NAME.fullmatch(value):
        raise HTTPException(400, f"Invalid {label}")
    return value


def memory_stats() -> tuple[int, int, float]:
    values = {}
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, raw = line.split(":", 1)
            values[key] = int(raw.strip().split()[0]) * 1024
    except (OSError, ValueError):
        return 0, 0, 0
    total, available = values.get("MemTotal", 0), values.get("MemAvailable", 0)
    used = max(total - available, 0)
    return total, used, used / total * 100 if total else 0


def human_bytes(value: int) -> str:
    size = float(value)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def service_states() -> list[tuple[str, str]]:
    states = []
    for name in ("lscpd", "lsws", "mariadb", "postfix", "dovecot", "rspamd", "redis",
                 "netdata", "leodigi-cpt-dashboard"):
        result = subprocess.run(["systemctl", "is-active", name], text=True, capture_output=True)
        state = result.stdout.strip() or "inactive"
        if result.returncode == 0 or state not in {"unknown", "inactive"}:
            states.append((name, state))
    return states


def profiles() -> list[str]:
    return sorted(p.stem.removeprefix("backup-") for p in CONFIG_DIR.glob("backup-*.env"))


def remotes() -> list[str]:
    rc, output = command(["backup", "remote", "list"], 30)
    return [line.strip().rstrip(":") for line in output.splitlines() if rc == 0 and line.strip()]


def version() -> str:
    try:
        return Path("/opt/leodigi-cyberpanel-toolkit/VERSION").read_text().strip()
    except OSError:
        return "unknown"


def latest_log() -> str:
    files = sorted(LOG_DIR.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    try:
        return "\n".join(files[0].read_text(errors="replace").splitlines()[-250:]) if files else "Chưa có log."
    except OSError as exc:
        return str(exc)


def shell(request: Request, section: str, title: str, body: str) -> str:
    links = "".join(f'<a class="{"active" if key == section else ""}" href="{("/" if key == "overview" else "/section/" + key)}">'
                    f'<i>{icon}</i><span>{html.escape(label)}</span></a>' for key, label, icon in NAV)
    return f"""<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport"
content="width=device-width,initial-scale=1"><title>{html.escape(title)} · LeoDigi</title><style>{CSS}</style></head>
<body><div class="layout"><aside class="sidebar"><div class="brand"><div class="logo">L</div><div>
<strong>LeoDigi Toolkit</strong><small>CyberPanel Operations</small></div></div><nav class="nav">{links}</nav>
<div class="side-foot">Version {html.escape(version())}<br><a href="https://leodigi.dev" target="_blank"
rel="noopener">leodigi.dev</a></div></aside><main class="main"><header class="top"><div>
<h1>{html.escape(title)}</h1><div class="subtitle">{html.escape(os.uname().nodename)} · CyberPanel Toolkit</div>
</div><div class="top-actions"><a class="btn" href="{request.url.path}">Làm mới</a><form method="post"
action="/logout"><input type="hidden" name="csrf_token" value="{csrf(request)}"><button>Đăng xuất</button>
</form></div></header>{body}<div class="footer">LeoDigi CyberPanel Toolkit · leodigi.dev</div></main></div></body></html>"""


def metric(label: str, value: str, detail: str, percent: float) -> str:
    return (f'<div class="card metric span3"><div class="label">{html.escape(label)}</div>'
            f'<div class="value">{html.escape(value)}</div><div class="detail">{html.escape(detail)}</div>'
            f'<div class="bar"><span style="width:{max(0, min(100, percent)):.1f}%"></span></div></div>')


def overview_body() -> str:
    mt, mu, mp = memory_stats()
    disk = shutil.disk_usage("/")
    dp = disk.used / disk.total * 100
    load1, load5, _ = os.getloadavg()
    cpu = os.cpu_count() or 1
    uptime = float(Path("/proc/uptime").read_text().split()[0]) / 86400
    services = service_states()
    service_html = "".join(f'<div class="service"><span><i class="dot {"up" if s == "active" else "down"}"></i>'
                           f'{html.escape(n)}</span><span class="badge {"ok" if s == "active" else "fail"}">'
                           f'{html.escape(s)}</span></div>' for n, s in services)
    try:
        last = (STATE_DIR / "last-backup").read_text().strip()
    except OSError:
        last = "Chưa có bản backup"
    up = sum(s == "active" for _, s in services)
    return f"""<div class="grid">{metric("CPU load", f"{load1:.2f}", f"{cpu} CPU · load 5m {load5:.2f}", load1/cpu*100)}
{metric("Bộ nhớ", f"{mp:.1f}%", f"{human_bytes(mu)} / {human_bytes(mt)}", mp)}
{metric("Ổ đĩa /", f"{dp:.1f}%", f"{human_bytes(disk.used)} / {human_bytes(disk.total)}", dp)}
{metric("Uptime", f"{uptime:.1f} ngày", f"{up}/{len(services)} dịch vụ hoạt động", up/max(len(services),1)*100)}
<section class="card span8"><h2>Trạng thái dịch vụ</h2><div class="status-list">{service_html}</div></section>
<section class="card span4"><h2>Backup gần nhất</h2><div class="notice">{html.escape(last)}</div>
<p class="subtitle">Profiles: {html.escape(', '.join(profiles()) or 'chưa cấu hình')}</p>
<a class="btn primary" href="/section/backup">Quản lý backup</a></section>
<section class="card span12"><h2>Truy cập nhanh</h2><div class="quick">
<a href="/section/backup"><b>Backup mã hóa</b><small>Run, snapshots và integrity check</small></a>
<a href="/section/wordpress"><b>WordPress</b><small>Danh sách và health check website</small></a>
<a href="/section/security"><b>Bảo mật</b><small>Malware, firewall và chẩn đoán</small></a>
</div></section></div>"""


def action_form(request: Request, action: str, label: str, fields: str = "", css: str = "") -> str:
    return (f'<form method="post" action="/action/{action}" class="forms"><input type="hidden" '
            f'name="csrf_token" value="{csrf(request)}">{fields}<button class="{css}">{html.escape(label)}</button></form>')


def backup_body(request: Request) -> str:
    available = profiles()
    options = "".join(f'<option value="{html.escape(p)}">{html.escape(p)}</option>' for p in available)
    select = f'<div><label>Backup profile</label><select name="profile">{options}</select></div>'
    actions = '<div class="empty">Chưa có profile. Chạy toolkitctl backup configure qua SSH.</div>'
    if available:
        actions = (action_form(request, "backup-list", "Xem snapshots", select) +
                   action_form(request, "backup-check", "Kiểm tra repository", select) +
                   action_form(request, "backup-run", "Chạy backup ngay", select, "good"))
    rows = "".join(f"<tr><td>{html.escape(r)}</td><td><span class='badge ok'>connected</span></td></tr>" for r in remotes())
    return f"""<div class="grid"><section class="card span8"><h2>Backup profiles</h2>
<div class="notice">Restic mã hóa + Rclone cloud. Tác vụ run/check có thể chạy lâu.</div><div class="forms">{actions}</div>
</section><section class="card span4"><h2>Cloud remotes</h2><table class="table"><thead><tr><th>Remote</th>
<th>Trạng thái</th></tr></thead><tbody>{rows or '<tr><td colspan="2">Chưa có remote</td></tr>'}</tbody></table>
</section></div>"""


READ_ACTIONS = {
    "health": ["health"], "doctor": ["doctor"], "wp-list": ["wp", "list"],
    "mail-status": ["mail", "status"], "mail-queue": ["mail", "queue"],
    "monitoring": ["monitoring", "status"], "firewall": ["firewall", "status"],
    "malware-report": ["malware", "report"],
}


def generic_body(request: Request, section: str) -> str:
    definitions = {
        "wordpress": ("Quản lý website WordPress", [("wp-list", "Liệt kê WordPress")]),
        "security": ("Kiểm tra bảo mật", [("doctor", "Chạy Doctor"), ("malware-report", "Báo cáo malware")]),
        "mail": ("Mail server", [("mail-status", "Trạng thái Mail"), ("mail-queue", "Mail queue")]),
        "ssl": ("Chứng chỉ SSL", []), "monitoring": ("Giám sát hệ thống", [("monitoring", "Thu thập trạng thái"), ("health", "Health check")]),
        "firewall": ("Firewall", [("firewall", "Xem firewall")]),
    }
    heading, actions = definitions[section]
    buttons = "".join(action_form(request, key, label, css="primary") for key, label in actions)
    domain = '<div><label>Domain</label><input name="target" placeholder="example.com" required></div>'
    if section == "wordpress":
        buttons += action_form(request, "wp-health", "Health check domain", domain)
    elif section == "security":
        buttons += action_form(request, "malware-scan", "Quét malware domain", domain, "danger")
    elif section == "ssl":
        buttons += action_form(request, "ssl-check-target", "Kiểm tra SSL domain", domain)
    return f'<div class="grid"><section class="card span12"><h2>{html.escape(heading)}</h2><div class="forms">{buttons}</div></section></div>'


@app.get("/login", response_class=HTMLResponse)
def login_page(request: Request):
    if authenticated(request):
        return RedirectResponse("/", 303)
    return f"""<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport"
content="width=device-width,initial-scale=1"><title>Đăng nhập · LeoDigi Toolkit</title><style>{CSS}
.login-wrap{{min-height:100vh;display:grid;place-items:center;padding:20px}}.login{{width:min(420px,100%);padding:30px}}
.login input{{width:100%;margin-bottom:14px}}.login button{{width:100%;padding:11px}}</style></head><body>
<div class="login-wrap"><div class="card login"><div class="brand"><div class="logo">L</div><div>
<strong>LeoDigi Toolkit</strong><small>CyberPanel Operations</small></div></div><form method="post">
<label>Tài khoản</label><input name="user" autocomplete="username" required><label>Mật khẩu</label>
<input type="password" name="password" autocomplete="current-password" required>
<button class="primary">Đăng nhập Dashboard</button></form></div></div></body></html>"""


@app.post("/login")
def login(request: Request, user: str = Form(...), password: str = Form(...)):
    expected_user = os.environ.get("CPT_DASHBOARD_USER", "admin")
    expected_hash = os.environ.get("CPT_DASHBOARD_PASSWORD_SHA256", "")
    actual = hashlib.sha256(password.encode()).hexdigest()
    if not (hmac.compare_digest(user, expected_user) and hmac.compare_digest(actual, expected_hash)):
        time.sleep(1)
        raise HTTPException(401, "Sai tài khoản hoặc mật khẩu")
    request.session.clear()
    request.session["auth"] = True
    csrf(request)
    return RedirectResponse("/", 303)


@app.get("/", response_class=HTMLResponse)
def home(request: Request):
    if not authenticated(request):
        return RedirectResponse("/login", 303)
    return shell(request, "overview", "Tổng quan hệ thống", overview_body())


@app.get("/section/{section}", response_class=HTMLResponse)
def section_page(request: Request, section: str):
    if not authenticated(request):
        return RedirectResponse("/login", 303)
    labels = {key: label for key, label, _ in NAV}
    if section == "backup":
        body = backup_body(request)
    elif section == "logs":
        body = f'<section class="card"><h2>Log gần nhất</h2><pre class="terminal">{html.escape(latest_log())}</pre></section>'
    elif section in {"wordpress", "security", "mail", "ssl", "monitoring", "firewall"}:
        body = generic_body(request, section)
    else:
        raise HTTPException(404)
    return shell(request, section, labels[section], body)


@app.post("/action/{action}", response_class=HTMLResponse)
def run_action(request: Request, action: str, csrf_token: str = Form(...),
               profile: str = Form(""), target: str = Form("")):
    require_auth(request)
    verify_csrf(request, csrf_token)
    timeout = 180
    if action in READ_ACTIONS:
        args = READ_ACTIONS[action]
    elif action in {"backup-list", "backup-check", "backup-run"}:
        profile = valid_name(profile, "profile")
        verb = action.removeprefix("backup-")
        args = ["backup", verb, profile]
        timeout = 1800 if verb in {"run", "check"} else 180
    elif action == "wp-health":
        args = ["wp", "health", valid_name(target, "domain")]
    elif action == "malware-scan":
        args, timeout = ["malware", "scan", valid_name(target, "domain")], 1800
    elif action == "ssl-check-target":
        args = ["ssl", "check", valid_name(target, "domain")]
    else:
        raise HTTPException(404)
    rc, output = command(args, timeout)
    status = "Thành công" if rc == 0 else f"Lỗi (exit {rc})"
    body = (f'<div class="notice {"" if rc == 0 else "warn"}"><b>{html.escape(status)}</b> · '
            f'<code>{html.escape("toolkitctl " + " ".join(args))}</code></div><section class="card">'
            f'<pre class="terminal">{html.escape(output or "Không có output")}</pre></section>')
    return shell(request, "overview", action, body)


@app.get("/api/overview")
def api_overview(request: Request):
    require_auth(request)
    mt, mu, mp = memory_stats()
    disk = shutil.disk_usage("/")
    return JSONResponse({"memory": {"total": mt, "used": mu, "percent": round(mp, 1)},
                         "disk": {"total": disk.total, "used": disk.used,
                                  "percent": round(disk.used / disk.total * 100, 1)},
                         "load": os.getloadavg(), "services": dict(service_states()), "profiles": profiles()})


@app.post("/logout")
def logout(request: Request, csrf_token: str = Form(...)):
    require_auth(request)
    verify_csrf(request, csrf_token)
    request.session.clear()
    return RedirectResponse("/login", 303)
