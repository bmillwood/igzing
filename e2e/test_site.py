"""Tests that drive the built site in a real browser.

These are for bugs at the boundary between Elm and the browser, which Elm-level
tests can't see: default actions, focus, event propagation. Run them with
`pytest e2e` after `nix-build -A site`, or set IGZING_SITE to another build.
"""

import functools
import http.server
import os
import threading

import pytest
from playwright import sync_api


@pytest.fixture(scope="session")
def site_url():
    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    handler = functools.partial(
        QuietHandler, directory=os.environ.get("IGZING_SITE", "result")
    )
    # Port 0 picks a free port, so stray servers can't shadow this one.
    server = http.server.ThreadingHTTPServer(("localhost", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    yield f"http://localhost:{server.server_port}/"
    server.shutdown()


@pytest.fixture(scope="session")
def browser():
    with sync_api.sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        yield browser
        browser.close()


@pytest.fixture
def page(browser, site_url):
    # The service worker would serve later loads from its cache, which only
    # makes it harder to tell what's being tested.
    context = browser.new_context(service_workers="block")
    page = context.new_page()
    page.goto(site_url)
    page.wait_for_selector(".keyboard")
    yield page
    context.close()


def open_settings(page):
    page.click("button[title=Settings]")
    page.wait_for_selector(".panel")
    return page.locator(".panel input[type=checkbox]")


def test_settings_checkboxes_toggle_and_persist(page):
    """Elm re-renders synchronously for handlers that stop propagation, and
    always re-applies `checked`, so a stopPropagationOn "click" anywhere above
    a checkbox resets it mid-click and the click does nothing."""
    boxes = open_settings(page)
    assert boxes.count() > 0
    initially = [boxes.nth(i).is_checked() for i in range(boxes.count())]
    for i in range(boxes.count()):
        boxes.nth(i).click()
        sync_api.expect(boxes.nth(i)).to_be_checked(checked=not initially[i])
    examples_shown = page.get_by_label("Show example words on keys").is_checked()
    sync_api.expect(page.locator(".keyboard.with-examples")).to_have_count(
        1 if examples_shown else 0
    )

    page.reload()
    page.wait_for_selector(".keyboard")
    boxes = open_settings(page)
    for i in range(boxes.count()):
        sync_api.expect(boxes.nth(i)).to_be_checked(checked=not initially[i])


def test_panel_closes_on_backdrop_click_only(page):
    open_settings(page)
    page.click(".panel h2")
    sync_api.expect(page.locator(".panel")).to_be_visible()
    page.click(".overlay", position={"x": 5, "y": 5})
    sync_api.expect(page.locator(".panel")).to_have_count(0)


def test_enter_after_clicking_a_key_submits(page):
    """Buttons cancel mousedown so that they don't take focus; otherwise a
    physical Enter would press the last clicked key again."""
    for label in ["s", "t", "r", "əʊ", "l"]:
        page.click(f".keyboard .key:has(.label:text-is('{label}'))")
    page.keyboard.press("Enter")
    sync_api.expect(
        page.locator(".board .tile.correct, .board .tile.present, .board .tile.absent")
    ).to_have_count(5)


def test_give_up_confirmation_cancels_on_anything_else(page):
    """Clicks and keypresses anywhere cancel the confirmation via a document
    listener, which also hears the mousedown on its own Yes button."""
    give_up = page.get_by_role("button", name="Give up", exact=True)
    yes = page.get_by_role("button", name="Yes", exact=True)

    give_up.click()
    page.click(".keyboard .key:has(.label:text-is('s'))")
    sync_api.expect(yes).to_have_count(0)

    give_up.click()
    page.keyboard.press("Backspace")
    sync_api.expect(yes).to_have_count(0)

    give_up.click()
    page.get_by_text("Give up and see the answer?").click()
    yes.click()
    sync_api.expect(page.get_by_text("The answer was")).to_be_visible()
