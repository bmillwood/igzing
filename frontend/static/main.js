"use strict";

const STORAGE_KEY = "sounding";

let saved = null;
try {
  saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
} catch (e) {
  console.warn("couldn't read saved games", e);
}

const app = Elm.Main.init({ node: document.getElementById("app"), flags: saved });

app.ports.save.subscribe((value) => {
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

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js").catch((e) => console.warn("no offline support", e));
  // Ask the browser not to evict the offline copy under storage pressure.
  navigator.storage?.persist?.();
}
