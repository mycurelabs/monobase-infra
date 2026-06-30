// NocoDB data-source bootstrap. Idempotent. Runs in the nocodb image (has node,
// global fetch, and the `pg` driver via NODE_PATH=/usr/src/app/node_modules).
//
// 1. ensure a read-only Postgres role exists on the target DB
// 2. ensure the NocoDB super-admin exists (signin, else first-signup)
// 3. ensure a base + an external read-only pg source pointing at that DB exist
//
// All identifiers (role, schema, db) come from chart values, not user input.
const { Client } = require('pg');

const E = process.env;
const NC_URL = E.NC_URL;
const ADMIN_EMAIL = E.ADMIN_EMAIL;
const ADMIN_PASSWORD = E.ADMIN_PASSWORD;
const BASE_TITLE = E.BASE_TITLE;
const SOURCE_ALIAS = E.SOURCE_ALIAS;
const SEARCH_PATH = (E.SEARCH_PATH || 'public').split(',').map(s => s.trim()).filter(Boolean);
const PG = {
  host: E.PG_HOST, port: +(E.PG_PORT || 5432), database: E.PG_DB,
  adminUser: E.PG_ADMIN_USER || 'postgres', adminPassword: E.PG_ADMIN_PASSWORD,
  roUser: E.RO_USER || 'nocodb_ro', roPassword: E.RO_PASSWORD,
};

const sleep = ms => new Promise(r => setTimeout(r, ms));
const sq = s => s.replace(/'/g, "''"); // single-quote escape for SQL literals

async function ensureRole() {
  const c = new Client({
    host: PG.host, port: PG.port, database: PG.database,
    user: PG.adminUser, password: PG.adminPassword,
  });
  await c.connect();
  try {
    const { rows } = await c.query('select 1 from pg_roles where rolname=$1', [PG.roUser]);
    const verb = rows.length ? 'ALTER' : 'CREATE';
    await c.query(`${verb} ROLE ${PG.roUser} LOGIN PASSWORD '${sq(PG.roPassword)}'`);
    await c.query(`GRANT CONNECT ON DATABASE ${PG.database} TO ${PG.roUser}`);
    for (const s of SEARCH_PATH) {
      await c.query(`GRANT USAGE ON SCHEMA ${s} TO ${PG.roUser}`);
      await c.query(`GRANT SELECT ON ALL TABLES IN SCHEMA ${s} TO ${PG.roUser}`);
      await c.query(`ALTER DEFAULT PRIVILEGES IN SCHEMA ${s} GRANT SELECT ON TABLES TO ${PG.roUser}`);
    }
    console.log(`[role] ${verb} ${PG.roUser} ok`);
  } finally {
    await c.end();
  }
}

async function api(path, opts = {}, token) {
  const r = await fetch(NC_URL + path, {
    ...opts,
    headers: { 'Content-Type': 'application/json', ...(token ? { 'xc-auth': token } : {}), ...(opts.headers || {}) },
  });
  const text = await r.text();
  let body; try { body = JSON.parse(text); } catch { body = text; }
  return { status: r.status, body };
}

async function waitHealth() {
  for (let i = 0; i < 60; i++) {
    try { const r = await fetch(NC_URL + '/api/v1/health'); if (r.ok) { console.log('[health] ok'); return; } } catch {}
    await sleep(5000);
  }
  throw new Error('nocodb health timeout');
}

async function auth() {
  let r = await api('/api/v1/auth/user/signin', { method: 'POST', body: JSON.stringify({ email: ADMIN_EMAIL, password: ADMIN_PASSWORD }) });
  if (r.body && r.body.token) { console.log('[auth] signed in'); return r.body.token; }
  r = await api('/api/v1/auth/user/signup', { method: 'POST', body: JSON.stringify({ email: ADMIN_EMAIL, password: ADMIN_PASSWORD }) });
  if (r.body && r.body.token) { console.log('[auth] signed up (first user)'); return r.body.token; }
  throw new Error('auth failed: ' + JSON.stringify(r.body));
}

async function main() {
  await ensureRole();
  await waitHealth();
  const token = await auth();

  const me = await api('/api/v1/auth/user/me', {}, token);
  const roles = (me.body && me.body.roles) || {};
  if (!(roles['org-level-creator'] || roles['super'])) {
    throw new Error('admin lacks creator role (' + JSON.stringify(roles) + '); the configured admin must be the FIRST signup — reset NocoDB metadata if another user was created first');
  }

  const list = await api('/api/v2/meta/bases', {}, token);
  let base = ((list.body && list.body.list) || []).find(b => b.title === BASE_TITLE);
  if (!base) {
    const c = await api('/api/v2/meta/bases', { method: 'POST', body: JSON.stringify({ title: BASE_TITLE }) }, token);
    if (!c.body || !c.body.id) throw new Error('base create failed: ' + JSON.stringify(c.body));
    base = c.body;
    console.log('[base] created', base.id);
  } else {
    console.log('[base] exists', base.id);
  }

  const srcs = await api(`/api/v2/meta/bases/${base.id}/sources`, {}, token);
  const arr = Array.isArray(srcs.body) ? srcs.body : ((srcs.body && srcs.body.list) || []);
  if (arr.some(s => s.alias === SOURCE_ALIAS)) {
    console.log('[source] already present, nothing to do');
    return;
  }
  const create = await api(`/api/v2/meta/bases/${base.id}/sources`, {
    method: 'POST',
    body: JSON.stringify({
      alias: SOURCE_ALIAS, type: 'pg', is_schema_readonly: true, is_data_readonly: true,
      config: { client: 'pg', connection: { host: PG.host, port: PG.port, user: PG.roUser, password: PG.roPassword, database: PG.database }, searchPath: SEARCH_PATH },
    }),
  }, token);
  if (create.status >= 400 || !create.body || create.body.error || create.body.msg) {
    throw new Error('source create failed: ' + JSON.stringify(create.body));
  }
  console.log('[source] created', create.body.id, '(tables import asynchronously)');
}

main().then(() => { console.log('bootstrap done'); process.exit(0); })
  .catch(e => { console.error('bootstrap failed:', e.message); process.exit(1); });
