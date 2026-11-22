// Service worker: keep a complete copy of the site so the game works offline.
//
// The build replaces VERSION with "sounding-" and a hash of the site's files,
// and FILES with their paths, so that each new build installs a fresh cache
// and the old one is deleted once it takes over. Caches are shared by the
// whole origin, which on GitHub Pages includes the owner's other projects, so
// only delete our own.

const VERSION = "@VERSION@";
const FILES = "@FILES@";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(VERSION)
      .then((cache) => cache.addAll(["./", ...FILES]))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith("sounding-") && k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

// Cache first: the files are all versioned together, so whatever's cached is
// consistent, and a new build arrives via a new service worker.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  event.respondWith(
    caches
      .open(VERSION)
      .then((cache) => cache.match(event.request, { ignoreSearch: true }))
      .then((cached) => cached ?? fetch(event.request)),
  );
});
