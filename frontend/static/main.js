"use strict";

// localStorage is shared by the whole origin, which includes this site's
// branch previews in pr/N/, so each copy of the site keeps its games under its
// own path.
const STORAGE_KEY = `igzing ${new URL(".", location.href).pathname}`;

let saved = null;
try {
  saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
} catch (e) {
  console.warn("couldn't read saved games", e);
}

// The theme setting styles the whole page, which is outside Elm's control, so
// apply it from the saved settings: now, before Elm first renders, so the page
// doesn't flash the wrong colours, and whenever they're saved.
function applyTheme(settings) {
  document.documentElement.dataset.theme = settings?.theme ?? "auto";
}
applyTheme(saved?.settings);

const app = Elm.Main.init({ node: document.getElementById("app"), flags: saved });

app.ports.save.subscribe((value) => {
  applyTheme(value.settings);
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(value));
  } catch (e) {
    console.warn("couldn't save games", e);
  }
});

app.ports.share.subscribe(async (text) => {
  try {
    // The share sheet is nice on phones, but on desktops it's often an odd
    // OS dialog when all you wanted was the clipboard.
    if (navigator.share && matchMedia("(pointer: coarse)").matches) {
      await navigator.share({ text });
      app.ports.shared.send("Shared");
    } else {
      await navigator.clipboard.writeText(text);
      app.ports.shared.send("Copied to clipboard");
    }
  } catch (e) {
    if (e.name !== "AbortError") app.ports.shared.send(`Couldn't share: ${e.message}`);
  }
});

// Elm asks for its next render's animation frame before sending this, so this
// frame comes after it.
app.ports.scrollBoard.subscribe(() =>
  requestAnimationFrame(() => {
    const board = document.getElementById("board");
    const latest = document.getElementById("latest-row");
    if (!board || !latest) return;
    board.scrollTop +=
      latest.getBoundingClientRect().bottom - board.getBoundingClientRect().bottom;
  }),
);

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js").catch((e) => console.warn("no offline support", e));
  // A new build's service worker takes over open pages as soon as it's
  // installed, and deletes the old build's files, so reload onto the new
  // build. Progress is saved after every change, so this loses at most a
  // half-typed guess. A page with no service worker yet is just being taken
  // over for the first time, and is already up to date.
  if (navigator.serviceWorker.controller) {
    navigator.serviceWorker.addEventListener("controllerchange", () => location.reload());
  }
  // Ask the browser not to evict the offline copy under storage pressure.
  navigator.storage?.persist?.();
}
