const CACHE = "uasa-v2";
const PRECACHE = [
  "./",
  "./index.html",
  "./manifest.json",
  "./icon-192.png",
  "./icon-512.png",
  "./icon-maskable-512.png",
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"
];

self.addEventListener("install", e => {
  e.waitUntil(
    caches.open(CACHE).then(c =>
      Promise.all(PRECACHE.map(url => c.add(url).catch(() => null)))
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  // Never intercept Supabase API/auth
  if (url.host.endsWith(".supabase.co")) return;

  // CDN: cache-first
  if (url.host === "cdn.jsdelivr.net") {
    e.respondWith(
      caches.match(req).then(hit => hit || fetch(req).then(res => {
        if (res.ok) { const clone = res.clone(); caches.open(CACHE).then(c => c.put(req, clone)); }
        return res;
      }).catch(() => caches.match(req)))
    );
    return;
  }

  // Same origin: network-first, fall back to cache, then index.html
  if (url.origin === location.origin) {
    e.respondWith(
      fetch(req).then(res => {
        if (res.ok && (req.destination === "document" || req.destination === "script" || url.pathname.endsWith(".html"))) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(req, clone));
        }
        return res;
      }).catch(() => caches.match(req).then(hit => hit || caches.match("./index.html")))
    );
  }
});
