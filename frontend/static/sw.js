// Service worker: keep a complete copy of the site so the game works offline.
//
// assemble.sh replaces the two placeholder strings below: VERSION's with
// "igzing-" and a hash of the site's files, and FILES's with a JSON array of
// their paths. So each new build installs a fresh cache, and the old one is
// deleted once it takes over. assemble.sh replaces every occurrence, so the
// placeholders mustn't appear anywhere else in this file.

const VERSION = "@VERSION@";
const FILES = "@FILES@";

// If assemble.sh didn't stamp this file, fail to install, so the site still
// works online, rather than caching the wrong files. An unstamped FILES is a
// string, which addAll below would take one character at a time.
if (!VERSION.startsWith("igzing-") || !Array.isArray(FILES)) {
  throw new Error("sw.js wasn't stamped by assemble.sh");
}

// Caches are shared by the whole origin. On GitHub Pages that includes the
// owner's other projects, and this site's own branch previews in pr/N/, each
// with its own service worker. So each one names its caches after its scope,
// and only deletes those.
const SCOPE = ` ${self.registration.scope}`;
const CACHE = VERSION + SCOPE;

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      // Bypass the HTTP cache, which could otherwise hand us the previous
      // build's files to store under this build's name.
      .then((cache) => cache.addAll(["./", ...FILES].map((f) => new Request(f, { cache: "reload" }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => {
        const ours = (k) => k.startsWith("igzing-") && k.endsWith(SCOPE);
        return Promise.all(keys.filter((k) => ours(k) && k !== CACHE).map((k) => caches.delete(k)));
      })
      .then(() => self.clients.claim()),
  );
});

// Cache first: the files are all versioned together, so whatever's cached is
// consistent, and a new build arrives via a new service worker. Pages reload
// when that takes over (see main.js), so they don't mix two builds' files.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  event.respondWith(
    caches
      .open(CACHE)
      .then((cache) => cache.match(event.request, { ignoreSearch: true }))
      .then((cached) => cached ?? fetch(event.request)),
  );
});
