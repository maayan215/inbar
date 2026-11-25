// Likes counter for inbarviente.com (Cloudflare Worker + KV).
//   GET  /likes                         -> { counts: { <photoId>: n, ... } }
//   POST /like  { id, visitor, liked }  -> { id, count, liked }
// One like per visitor per photo; sending liked:false undoes it.
// Counts live in one KV key ("counts"); each visitor's like is a flag key that expires after a year.

const ID_RE = /^AF1Qip[A-Za-z0-9_-]{20,80}$/;   // Google Photos media ids
const VISITOR_RE = /^[a-z0-9]{16,40}$/;          // random id generated in the visitor's browser
const MAX_PHOTOS = 5000;                          // stop junk ids from bloating the counts
const ALLOWED_ORIGINS = [
  'https://inbarviente.com',
  'https://www.inbarviente.com',
  'https://maayan215.github.io',
];

function corsHeaders(req) {
  const origin = req.headers.get('Origin') || '';
  const h = {
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
  // also allow local previews (http://localhost:<port>) for testing
  if (ALLOWED_ORIGINS.includes(origin) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
    h['Access-Control-Allow-Origin'] = origin;
  }
  return h;
}

function json(data, status, headers) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...headers },
  });
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const cors = corsHeaders(req);

    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });

    if (url.pathname === '/likes' && req.method === 'GET') {
      const counts = (await env.LIKES.get('counts', { type: 'json' })) || {};
      return json({ counts }, 200, cors);
    }

    if (url.pathname === '/like' && req.method === 'POST') {
      let body;
      try { body = await req.json(); } catch { return json({ error: 'bad json' }, 400, cors); }
      const { id, visitor, liked } = body || {};
      if (!ID_RE.test(id || '') || !VISITOR_RE.test(visitor || '') || typeof liked !== 'boolean') {
        return json({ error: 'bad request' }, 400, cors);
      }

      const flagKey = `v:${visitor}:${id}`;
      const had = (await env.LIKES.get(flagKey)) !== null;
      const counts = (await env.LIKES.get('counts', { type: 'json' })) || {};
      if (!(id in counts) && Object.keys(counts).length >= MAX_PHOTOS) return json({ error: 'full' }, 400, cors);
      let n = counts[id] || 0;

      if (liked === had) return json({ id, count: n, liked: had }, 200, cors);   // nothing to change

      if (liked) { n += 1; await env.LIKES.put(flagKey, '1', { expirationTtl: 60 * 60 * 24 * 365 }); }
      else { n = Math.max(0, n - 1); await env.LIKES.delete(flagKey); }

      counts[id] = n;
      await env.LIKES.put('counts', JSON.stringify(counts));
      return json({ id, count: n, liked }, 200, cors);
    }

    return json({ error: 'not found' }, 404, cors);
  },
};
