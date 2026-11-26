// Service worker: keep a complete copy of the site so the game works offline.
//
// assemble.sh replaces the two placeholder strings below: VERSION's with
// "igzing-" and a hash of the site's files, and FILES's with a JSON array of
// the paths of those to install up front, which is all but the accents'
// dictionaries. So each new build installs a fresh cache, and the old one is
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

const ours = (key) => key.startsWith("igzing-") && key.endsWith(SCOPE);

// Bypass the HTTP cache, which could otherwise hand us the previous build's
// files to store under this build's name.
const fresh = (url) => new Request(url, { cache: "reload" });

self.addEventListener("install", (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      const upFront = ["./", ...FILES];
      await cache.addAll(upFront.map(fresh));
      // Also keep the new build's copy of whatever the old one kept because
      // it got used, i.e. the dictionaries for the accents played in, so
      // they keep working offline. Individually, so that one that's gone
      // from this build doesn't stop the rest.
      const used = new Set();
      for (const key of (await caches.keys()).filter(ours)) {
        for (const request of await (await caches.open(key)).keys()) used.add(request.url);
      }
      for (const url of upFront.map((f) => new URL(f, self.registration.scope).href)) used.delete(url);
      await Promise.all(
        [...used].map((url) => cache.add(fresh(url)).catch((e) => console.warn("not keeping", url, e))),
      );
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => ours(k) && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

// Cache first: the files are all versioned together, so whatever's cached is
// consistent, and a new build arrives via a new service worker. Pages reload
// when that takes over (see main.js), so they don't mix two builds' files.
//
// A dictionary that isn't cached yet, on its first use, gets cached once
// fetched. Nothing else does: the scope also covers the list of branch
// previews in pr/, which shouldn't be frozen at whatever it was first seen as.
const DATA = new URL("data/", self.registration.scope).href;

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const cached = await cache.match(event.request, { ignoreSearch: true });
      if (cached) return cached;
      const response = await fetch(event.request);
      if (response.ok && event.request.url.startsWith(DATA)) {
        event.waitUntil(cache.put(event.request, response.clone()));
      }
      return response;
    })(),
  );
});
