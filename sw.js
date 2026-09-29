const CACHE_NAME = 'jagonutrition-v1';
const STATIC_ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './favicon.png',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './supabase/auth-client.js'
];

// Install event - precache shell assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS);
    }).then(() => self.skipWaiting())
  );
});

// Activate event - clean up legacy caches and claim clients
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cache) => {
          if (cache !== CACHE_NAME) {
            return caches.delete(cache);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch event handler
self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);

  // 1. NON-GET requests (POST, PUT, DELETE, etc.) MUST NEVER BE CACHED OR INTERCEPTED
  if (request.method !== 'GET') {
    return;
  }

  // 2. SUPABASE / API / REALTIME / AUTH REQUESTS MUST NEVER BE CACHED
  // Direct bypass to network to avoid any risk of stale inventory, auth, or sales data
  const isSupabaseOrApi = 
    url.hostname.includes('supabase.co') ||
    url.pathname.includes('/rest/v1/') ||
    url.pathname.includes('/auth/v1/') ||
    url.pathname.includes('/functions/v1/') ||
    url.pathname.includes('/realtime/v1/');

  if (isSupabaseOrApi) {
    return; // Browser default network request
  }

  // 3. For local static assets: Network-First strategy with Cache Fallback
  event.respondWith(
    fetch(request)
      .then((networkResponse) => {
        // If network response is valid, clone and update cache
        if (networkResponse && networkResponse.status === 200 && networkResponse.type === 'basic') {
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(request, responseToCache);
          });
        }
        return networkResponse;
      })
      .catch(() => {
        // Fallback to cache if network fails (e.g. offline)
        return caches.match(request).then((cachedResponse) => {
          if (cachedResponse) {
            return cachedResponse;
          }
          if (request.mode === 'navigate') {
            return caches.match('./index.html') || caches.match('./');
          }
        });
      })
  );
});
