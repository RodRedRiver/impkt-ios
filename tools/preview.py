#!/usr/bin/env python3
"""Live preview of the app's Test tab: a phone frame in the browser that reloads on save.

    python3 tools/preview.py [--port 8810] [--open]

Serves IMPKT/Resources the way the app's BundleFiles scheme handler does, so /Web/index.html,
/css/pilot.css, /fonts and /pilots.json resolve exactly as they do in the bundle. The page is the
app's own copy, not the website's. Edit IMPKT/Resources/Web/index.html or css/pilot.css, save, and
the frame reloads in under a second. Chrome supplies the real Web Bluetooth, so a band still pairs.

Only the Test tab can be previewed. Leaderboard, Update, Devices and Profile are SwiftUI and need
Xcode (this Mac has none; the GitHub Actions build is the way to see those). The status bar and tab
bar drawn around the page are an approximation of iOS, there to size the page honestly: they tell
you how much room the page really gets between the clock and the tab bar.
"""
import argparse
import json
import os
import threading
import time
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "IMPKT", "Resources")
ROOT = os.path.normpath(ROOT)
TOOLS = os.path.dirname(os.path.abspath(__file__))
FILES = {n: os.path.join(ROOT, n) for n in ["Web/index.html", "css/pilot.css", "bridge.js", "pilots.json", "firmware-version.txt"]}
FILES["preview-tabs.js"] = os.path.join(TOOLS, "preview-tabs.js")        # the HTML mirrors of the four SwiftUI tabs
FILES["preview-tabs.css"] = os.path.join(TOOLS, "preview-tabs.css")
WATCH = list(FILES)

# (width, height, safe-top, tab-bar-with-home-indicator)
DEVICES = {
    "15": ("iPhone 15", 393, 852, 59, 83),
    "promax": ("iPhone 15 Pro Max", 430, 932, 59, 83),
    "se": ("iPhone SE", 375, 667, 20, 49),
}

# Before any page script: the app sets this handler, which is what puts class "in-app" on <html>
# (bridge.js keys off it). Chrome keeps its own navigator.bluetooth, and bridge.js leaves it alone.
STUB = (b'<script>window.webkit={messageHandlers:{impkt:{postMessage:function(m){parent.postMessage({impkt:m},"*");}}}};</script>'
        b'<script src="/bridge.js"></script>')

WRAPPER = r"""<!doctype html>
<html><head><meta charset="utf-8"><title>IMPKT app preview</title>
<link rel="stylesheet" href="/__tabs.css">
<style>
  :root { --red:#C41E3A; --canvas:#f5f5f7; }
  * { box-sizing: border-box; }
  body { margin:0; min-height:100vh; background:#d9d9de; display:flex; align-items:center; justify-content:center;
         gap:56px; font:13px -apple-system,"Helvetica Neue",Helvetica,Arial,sans-serif; color:#1d1d1f; padding:24px; }
  #phone { position:relative; background:#000; border-radius:62px; padding:12px; box-shadow:0 30px 80px rgba(0,0,0,.28),0 0 0 2px #2c2c2e; flex:none; }
  #screen { position:relative; overflow:hidden; border-radius:50px; background:var(--canvas); }
  #bar { position:absolute; left:0; right:0; top:0; display:flex; align-items:flex-end; justify-content:space-between;
         padding:0 30px 8px 34px; font-weight:600; font-size:15px; background:var(--canvas); z-index:2; }
  #island { position:absolute; top:11px; left:50%; width:116px; height:34px; margin-left:-58px; background:#000; border-radius:20px; z-index:3; }
  #frame { position:absolute; left:0; border:0; width:100%; background:var(--canvas); }
  #tabs { position:absolute; left:0; right:0; bottom:0; background:var(--canvas); border-top:1px solid rgba(60,60,67,.18);
          display:flex; justify-content:space-around; padding-top:7px; z-index:2; }
  .tab { cursor:pointer; display:flex; flex-direction:column; align-items:center; gap:3px; font-size:10px; color:#8e8e93; width:25% }
  .tab i { width:24px; height:24px; border-radius:7px; border:2px solid currentColor; display:block; }
  .tab.on { color:var(--red); } .tab.on i { background:var(--red); border-color:var(--red); }
  #home { position:absolute; bottom:8px; left:50%; width:134px; height:5px; margin-left:-67px; background:#000; border-radius:3px; z-index:3; }
  #panel { width:290px; display:flex; flex-direction:column; gap:14px; }
  #panel h1 { margin:0; font-size:20px; letter-spacing:-.02em; } #panel h1 span { color:var(--red); }
  #panel p { margin:0; color:#555; line-height:1.45; }
  .row { display:flex; gap:8px; flex-wrap:wrap; }
  button { font:inherit; font-weight:600; padding:8px 14px; border-radius:999px; border:1px solid #bbb; background:#fff; cursor:pointer; }
  button.on { background:#1d1d1f; color:#fff; border-color:#1d1d1f; }
  #stat { font-size:12px; color:#6b6b6b; } #stat b { color:#1d1d1f; }
  .dot { display:inline-block; width:8px; height:8px; border-radius:4px; background:#2fb344; margin-right:6px; }
  .dot.off { background:var(--red); }
  small { color:#777; line-height:1.4; display:block; }
</style></head>
<body>
<div id="phone"><div id="screen">
  <div id="island"></div>
  <div id="bar"><span id="clock">9:41</span><span>5G &nbsp;&#9646;&#9646;&#9646;</span></div>
  <iframe id="frame" title="Test tab"></iframe>
  <div id="native"></div>
  <div id="tabs">
    <div class="tab on" data-i="0"><i></i>Test</div><div class="tab" data-i="1"><i></i>Leaderboard</div>
    <div class="tab" data-i="2"><i></i>Devices</div><div class="tab" data-i="3"><i></i>Profile</div>
  </div>
  <div id="home"></div>
</div></div>
<div id="panel">
  <h1>IMPKT<span>.</span> app preview</h1>
  <p>Click any tab. <b>Test</b> is the real page, live (Code, Profile and Drills; the last two open past the code with a sample pilot): save <b>Web/index.html</b> or <b>css/pilot.css</b> and it reloads. The other four are HTML mirrors of the SwiftUI screens with made-up data; pick a state below.</p>
  <div class="row" id="devs"></div>
  <div class="row"><button id="reload">Reload now</button><button id="auto" class="on">Auto reload: on</button><button id="reset">Forget code</button></div>
  <div id="states"></div>
  <div id="stat"><span class="dot" id="dot"></span><span id="msg">connecting</span></div>
  <small>Leaderboard, Update, Devices and Profile are drawn from the Swift source, not rendered from it, so
  they can drift from the real app until a build confirms them. The bars are an approximation of iOS.</small>
</div>
<script src="/__tabs.js"></script>
<script>
const DEV = __DEVICES__;
const q = new URLSearchParams(location.search);
const H = new URLSearchParams(location.hash.slice(1));
let dev = (H.get('d') || q.get('d')) && DEV[H.get('d') || q.get('d')] ? (H.get('d') || q.get('d')) : '15';
let tab = +(H.get('t') || 0), st = +(H.get('s') || 0), scr = +(H.get('p') || 0);
const SCREENS = [['Code', ''], ['Profile', 'setup'], ['Drills', 'drills']];
let auto = true;
const frame = document.getElementById('frame');
function pageUrl() { const c = q.get('c'); return '/Web/index.html?__p=' + Date.now() + (c ? '&c=' + encodeURIComponent(c) : '') + (scr ? '&skip=1&pane=' + SCREENS[scr][1] + (q.get('step') ? '&step=' + q.get('step') : '') : ''); }
function layout() {
  const [name, w, h, top, bot] = DEV[dev];
  const s = document.getElementById('screen'), bar = document.getElementById('bar'), tabs = document.getElementById('tabs');
  s.style.width = w + 'px'; s.style.height = h + 'px';
  const nat = document.getElementById('native'); nat.style.top = top + 'px'; nat.style.height = (h - top - bot) + 'px';
  bar.style.height = top + 'px'; tabs.style.height = bot + 'px';
  frame.style.top = top + 'px'; frame.style.height = (h - top - bot) + 'px';
  document.getElementById('home').style.display = bot > 60 ? 'block' : 'none';
  document.getElementById('island').style.display = top > 40 ? 'block' : 'none';
  document.querySelectorAll('#devs button').forEach(b => b.classList.toggle('on', b.dataset.k === dev));
}
const devs = document.getElementById('devs');
for (const k in DEV) { const b = document.createElement('button'); b.textContent = DEV[k][0]; b.dataset.k = k;
  b.onclick = () => { dev = k; remember(); layout(); load(); }; devs.appendChild(b); }
function load() { frame.src = pageUrl(); }
const nat = document.getElementById('native');
const remember = () => history.replaceState(0, '', location.pathname + location.search + '#t=' + tab + '&s=' + st + '&p=' + scr + '&d=' + dev);
function renderNative() { const T = TABS[tab]; if (!T) return; const names = Object.keys(T.states); if (st >= names.length) st = 0; nat.innerHTML = T.states[names[st]](); }
function renderStates() {
  const box = document.getElementById('states'); box.innerHTML = ''; const T = TABS[tab];
  if (!T) { SCREENS.forEach(([n], i) => { const b = document.createElement('button'); b.textContent = n; b.className = i === scr ? 'on' : ''; b.onclick = () => { scr = i; load(); renderStates(); remember(); }; box.appendChild(b); }); return; }
  Object.keys(T.states).forEach((n, i) => { const b = document.createElement('button'); b.textContent = n; b.className = i === st ? 'on' : ''; b.onclick = () => { st = i; show(tab); }; box.appendChild(b); });
}
function show(i) {
  tab = i; document.querySelectorAll('.tab').forEach(t => t.classList.toggle('on', +t.dataset.i === i));
  frame.style.display = i ? 'none' : 'block'; nat.classList.toggle('on', i > 0);
  if (i) { nat.scrollTop = 0; renderNative(); } renderStates(); remember();
}
document.querySelectorAll('.tab').forEach(t => t.onclick = () => { st = 0; show(+t.dataset.i); });
addEventListener('message', e => {              // the page asking the app for one of its tabs
  const m = e.data && e.data.impkt; if (!m || m.op !== 'openTab') return;
  const i = { leaderboard: 1, devices: 2, profile: 3 }[m.args && m.args.tab]; if (i) { st = 0; show(i); }
});
fetch('/firmware-version.txt').then(r => r.ok ? r.text() : '').then(v => { if (v.trim()) { window.FW_VERSION = v.trim(); if (tab) renderNative(); } });
document.getElementById('reload').onclick = load;
document.getElementById('auto').onclick = e => { auto = !auto; e.target.classList.toggle('on', auto); e.target.textContent = 'Auto reload: ' + (auto ? 'on' : 'off'); };
document.getElementById('reset').onclick = () => { try { frame.contentWindow.localStorage.clear(); frame.contentWindow.sessionStorage.clear(); } catch (e) {} load(); };
const msg = document.getElementById('msg'), dot = document.getElementById('dot');
function listen() {
  const es = new EventSource('/__events');
  es.onopen = () => { dot.classList.remove('off'); msg.innerHTML = 'watching <b>' + 'files</b>'; };
  es.onmessage = e => { const f = JSON.parse(e.data); const t = new Date().toLocaleTimeString();
    msg.innerHTML = 'reloaded <b>' + t + '</b> after ' + f.file; if (!auto) return; if (f.file.startsWith('preview-tabs')) location.reload(); else load(); };
  es.onerror = () => { dot.classList.add('off'); msg.textContent = 'preview server stopped'; };
}
layout(); load(); show(tab); if (!q.has('shot')) listen();      // ?shot is for headless screenshots, where an open stream keeps the page loading
</script></body></html>
"""


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def log_message(self, *a):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")      # a stale file is a lie in a preview
        super().end_headers()

    def _send(self, body, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            page = WRAPPER.replace("__DEVICES__", json.dumps({k: list(v) for k, v in DEVICES.items()}))
            return self._send(page.encode(), "text/html; charset=utf-8")
        if path == "/__events":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            seen = snapshot()
            try:
                while True:
                    time.sleep(0.25)
                    now = snapshot()
                    for name in WATCH:
                        if now.get(name) != seen.get(name):
                            self.wfile.write(("data: %s\n\n" % json.dumps({"file": name})).encode())
                            self.wfile.flush()
                    seen = now
                    if int(time.time()) % 15 == 0:                  # keep-alive so a dead tab is noticed
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                return
        if path in ("/__tabs.js", "/__tabs.css"):
            name = "preview-tabs." + path.rsplit(".", 1)[1]
            with open(FILES[name], "rb") as f:
                return self._send(f.read(), "text/javascript; charset=utf-8" if name.endswith("js") else "text/css; charset=utf-8")
        if path == "/Web/index.html":
            with open(os.path.join(ROOT, "Web", "index.html"), "rb") as f:
                html = f.read()
            html = html.replace(b"<head>", b"<head>" + STUB, 1)
            qs = parse_qs(urlparse(self.path).query)
            if qs.get("skip"):
                call = b"\n  resume();\n"
                assert html.count(call) == 1, "the page's resume() call moved, so the preview cannot skip the code"
                pane = (qs.get("pane") or [""])[0]
                go = (b"  renderDrills();\n" if pane == "drills" else b"") + (b"  show(document.getElementById('%s'));\n" % pane.encode() if pane in ("drills", "setup") else b"")
                step = (qs.get("step") or [""])[0]
                if step in ("1", "2", "3"):
                    go += b"  showStep(%s);\n" % step.encode()
                html = html.replace(call, call + b"  run({name:'Alex Sample',first:'Alex',serial:'IMPKT-0000',gym:'Sample Boxing Club'}" + (b"" if qs.get("anim") else b", true") + b");\n" + go, 1)
            return self._send(html, "text/html; charset=utf-8")
        return super().do_GET()


def snapshot():
    out = {}
    for name in WATCH:
        try:
            st = os.stat(FILES[name])
            out[name] = (st.st_mtime_ns, st.st_size)
        except OSError:
            out[name] = None
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8810)
    ap.add_argument("--open", action="store_true")
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    srv.daemon_threads = True
    url = "http://127.0.0.1:%d/" % a.port
    print("IMPKT app preview on", url)
    if a.open:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    srv.serve_forever()


if __name__ == "__main__":
    main()
