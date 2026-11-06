// About Inbox — service worker
// 1) recebe o "Compartilhar" do WhatsApp (POST ./share) e guarda no IndexedDB
// 2) cache do app para abrir offline
// 3) abre o app ao tocar numa notificação de lembrete
const CACHE = 'about-inbox-v1';
const ARQUIVOS = ['./', './index.html', './manifest.webmanifest', './icon-192.png', './icon-512.png', './apple-touch-icon.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ARQUIVOS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

function abrirDB() {
  return new Promise((ok, erro) => {
    const r = indexedDB.open('about-inbox', 1);
    r.onupgradeneeded = () => {
      const db = r.result;
      if (!db.objectStoreNames.contains('itens')) db.createObjectStore('itens', { keyPath: 'id' });
      if (!db.objectStoreNames.contains('blobs')) db.createObjectStore('blobs', { keyPath: 'id' });
      if (!db.objectStoreNames.contains('fila')) db.createObjectStore('fila', { keyPath: 'id' });
    };
    r.onsuccess = () => ok(r.result);
    r.onerror = () => erro(r.error);
  });
}
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);

async function receberCompartilhamento(req) {
  const form = await req.formData();
  const texto = [form.get('title'), form.get('text'), form.get('url')].filter(Boolean).join('\n').trim();
  const arquivos = form.getAll('files').filter(f => f && typeof f !== 'string' && f.size > 0);
  const db = await abrirDB();
  const anexos = [];
  for (const f of arquivos) {
    const id = uid();
    await new Promise((ok, erro) => {
      const tx = db.transaction('blobs', 'readwrite');
      tx.objectStore('blobs').put({ id, blob: f, nome: f.name || 'arquivo', tipo: f.type || '' });
      tx.oncomplete = ok; tx.onerror = () => erro(tx.error);
    });
    anexos.push({ id, nome: f.name || 'arquivo', tipo: f.type || '', tamanho: f.size });
  }
  await new Promise((ok, erro) => {
    const tx = db.transaction('fila', 'readwrite');
    tx.objectStore('fila').put({ id: uid(), texto, anexos, criado: new Date().toISOString() });
    tx.oncomplete = ok; tx.onerror = () => erro(tx.error);
  });
  return Response.redirect('./?compartilhado=1', 303);
}

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method === 'POST' && url.pathname.endsWith('/share')) {
    e.respondWith(receberCompartilhamento(e.request).catch(() => Response.redirect('./?compartilhado=erro', 303)));
    return;
  }
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;
  // rede primeiro (para pegar versões novas), cache se estiver offline
  e.respondWith(
    fetch(e.request).then(r => {
      if (r.ok) { const c = r.clone(); caches.open(CACHE).then(k => k.put(e.request, c)); }
      return r;
    }).catch(() => caches.match(e.request, { ignoreSearch: true }).then(r => r || caches.match('./')))
  );
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const alvo = './?item=' + encodeURIComponent((e.notification.data && e.notification.data.id) || '');
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cs => {
    for (const c of cs) { if ('focus' in c) { c.postMessage({ abrir: e.notification.data && e.notification.data.id }); return c.focus(); } }
    return self.clients.openWindow(alvo);
  }));
});
