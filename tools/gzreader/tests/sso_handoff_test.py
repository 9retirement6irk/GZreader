"""The single sign-on hand-off page (docs/oauth2-callback.html) in a real browser:
it only opens a sign-in request that comes back to it, asks before going to a
sign-in server it hasn't used, and only returns to a Kindle on the home network.

    python3 sso_handoff_test.py <port>
"""
import functools
import http.server
import os
import sys
import threading
import urllib.parse

from playwright.sync_api import sync_playwright

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18175
DOCS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "docs")
passed = failed = 0


def check(cond, name):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL: " + name)


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


srv = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), functools.partial(Quiet, directory=DOCS))
threading.Thread(target=srv.serve_forever, daemon=True).start()
PAGE = "http://127.0.0.1:%d/oauth2-callback.html" % PORT
SELF = "http://127.0.0.1:%d/oauth2-callback" % PORT
KINDLE = "http://192.168.1.20:8642/oauth2-callback"


def sign_in(host="idp.example.com", **over):
    q = {"response_type": "code", "client_id": "grimmory", "redirect_uri": SELF, "scope": "openid",
         "code_challenge": "abc", "code_challenge_method": "S256", "state": "st-1", "nonce": "n"}
    q.update(over)
    q = {k: v for k, v in q.items() if v is not None}
    return "https://%s/authorize?%s" % (host, urllib.parse.urlencode(q))


def handoff(go, back=KINDLE):
    # (a new visit each time: only the #part changes, and the browser wouldn't load the page again)
    page.goto("about:blank")
    return PAGE + "#back=" + urllib.parse.quote(back, safe="") + "&go=" + urllib.parse.quote(go, safe="")


with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page()
    reached = []

    def fake(route):
        reached.append(route.request.url)
        route.fulfill(status=200, content_type="text/html", body="<h1>outside</h1>")
    page.route("https://**/*", fake)
    page.route("http://192.168.1.20:8642/**", fake)

    def title():
        return page.locator("#title").inner_text()

    # not a sign-in request: refused, nothing opened
    for name, go in [("any other site", "https://attacker.example/landing"),
                     ("a request coming back somewhere else", sign_in(redirect_uri="https://attacker.example/cb")),
                     ("no PKCE", sign_in(code_challenge=None)),
                     ("a token instead of a code", sign_in(response_type="token")),
                     ("plain http", sign_in().replace("https://", "http://"))]:
        reached.clear()
        page.goto(handoff(go))
        page.wait_for_function("document.querySelector('#title').innerText !== 'Signing in…'")
        check(title() == "Can't sign in" and not reached, "not opened: " + name)

    # a sign-in server not used from here yet: asks first
    reached.clear()
    page.goto(handoff(sign_in()))
    page.wait_for_selector("#act:not([hidden])")
    check(title() == "Sign in at idp.example.com" and not reached, "a new sign-in server: named, not opened by itself")
    check(page.get_attribute("#go", "href") == sign_in(), "…Continue opens exactly the sign-in request")
    page.click("#go")
    page.wait_for_url("https://idp.example.com/**")
    check(reached and reached[-1].startswith("https://idp.example.com/authorize"), "…and opens it when tapped")

    # the same server again: straight there
    reached.clear()
    page.goto(handoff(sign_in(state="st-2")))
    page.wait_for_url("https://idp.example.com/**")
    check(reached and "state=st-2" in reached[-1], "a sign-in server used before: opened straight away")

    # back from the provider: to the Kindle, with the code
    reached.clear()
    page.goto("about:blank")
    page.goto(PAGE + "?code=the-code&state=st-2")
    page.wait_for_url("http://192.168.1.20:8642/**")
    check(reached and reached[-1] == KINDLE + "?code=the-code&state=st-2", "back to the Kindle's own page with the code")

    # a Kindle address that isn't on the home network: refused
    reached.clear()
    page.goto(handoff(sign_in(state="st-3"), back="http://attacker.example:8642/oauth2-callback"))
    page.wait_for_function("document.querySelector('#title').innerText !== 'Signing in…'")
    check(title() == "Can't sign in" and not reached, "back to anything but a Kindle on the home network: refused")
    browser.close()

srv.shutdown()
print("%d passed, %d failed" % (passed, failed))
sys.exit(0 if failed == 0 else 1)
