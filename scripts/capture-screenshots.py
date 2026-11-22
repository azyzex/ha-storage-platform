"""Capture real screenshots of the running platform (for the README, posts and the demo video).

Run inside the environment where `make up` ran:  python3 scripts/capture-screenshots.py [out_dir]
Shots: web app with files, Grafana dashboard (healthy, then during a storage-node failure), Prometheus alerts
in Grafana, Argo CD application tree. Needs: pip install playwright && python -m playwright install --with-deps chromium
"""
import base64
import pathlib
import subprocess
import sys
import time

from playwright.sync_api import sync_playwright

BASE = "http://localhost:8080"
OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "docs/img")
OUT.mkdir(parents=True, exist_ok=True)


def go(page, url: str, settle_ms: int) -> None:
    """Navigate, tolerating the abort that single-page apps (Grafana, Argo CD) cause by redirecting in-browser."""
    try:
        page.goto(url, wait_until="commit", timeout=30000)
    except Exception as exc:  # net::ERR_ABORTED from a client-side redirect
        print("navigation note:", str(exc).splitlines()[0])
    page.wait_for_timeout(settle_ms)


def secret(ns: str, name: str, key: str) -> str:
    raw = subprocess.check_output(["kubectl", "-n", ns, "get", "secret", name, "-o", f"jsonpath={{.data.{key}}}"])
    return base64.b64decode(raw).decode()


def seed_files() -> None:
    have = subprocess.run(["curl", "-fsS", f"{BASE}/api/files"], capture_output=True, text=True).stdout
    if have.count('"id"') >= 3:
        return
    for name, size in [("contract-2027.pdf", 2_000_000), ("network-diagram.png", 640_000), ("backup-plan.docx", 180_000)]:
        path = pathlib.Path("/tmp") / name
        path.write_bytes(bytes(size))
        subprocess.run(["curl", "-fsS", "-o", "/dev/null", "-F", f"file=@{path}", f"{BASE}/api/files"], check=False)


def grafana_login(page) -> None:
    go(page, f"{BASE}/grafana/login", 3000)
    page.fill("input[name='user']", "admin")
    page.fill("input[name='password']", secret("monitoring", "grafana-admin", "admin-password"))
    page.click("button[type='submit']")
    page.wait_for_timeout(4000)


def dashboard(page, file: str) -> None:
    # Grafana renders panels lazily (only when in view): use a viewport tall enough for the whole dashboard,
    # then wait until the time-series panels have drawn their canvases.
    page.set_viewport_size({"width": 1600, "height": 2000})
    go(page, f"{BASE}/grafana/d/ha-storage/ha-storage-platform?orgId=1&from=now-15m&to=now&kiosk", 5000)
    try:
        page.wait_for_function("document.querySelectorAll('canvas').length >= 6", timeout=40000)
    except Exception:
        print("warning: fewer panels drew than expected")
    page.wait_for_timeout(4000)
    page.screenshot(path=str(OUT / file), full_page=True)
    page.set_viewport_size({"width": 1600, "height": 1000})
    print("saved", file)


with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 1600, "height": 1000}, device_scale_factor=1.5)

    seed_files()
    go(page, BASE, 5000)
    page.screenshot(path=str(OUT / "01-web-app.png"), full_page=True)
    print("saved 01-web-app.png")

    grafana_login(page)
    dashboard(page, "02-grafana-healthy.png")

    subprocess.run(["docker", "stop", "gluster-2"], check=True, stdout=subprocess.DEVNULL)
    print("gluster-2 stopped, waiting for the alert...")
    time.sleep(75)
    dashboard(page, "03-grafana-node-down.png")
    go(page, f"{BASE}/grafana/alerting/list?view=list&search=state:firing", 8000)
    page.screenshot(path=str(OUT / "04-alert-firing.png"), full_page=True)
    print("saved 04-alert-firing.png")
    subprocess.run(["docker", "start", "gluster-2"], check=True, stdout=subprocess.DEVNULL)

    go(page, f"{BASE}/argocd/login", 4000)
    page.fill("input[name='username']", "admin")
    page.fill("input[name='password']", secret("argocd", "argocd-initial-admin-secret", "password"))
    page.click("button[type='submit']")
    page.wait_for_timeout(4000)
    go(page, f"{BASE}/argocd/applications/argocd/ha-storage?view=tree", 9000)
    page.screenshot(path=str(OUT / "05-argocd.png"), full_page=False)
    print("saved 05-argocd.png")
    browser.close()
