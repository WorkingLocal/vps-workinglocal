const http = require('http');
const fs = require('fs');
const { exec } = require('child_process');

const PORT = 3456;
const N8N_HOST = '172.18.0.3';
const N8N_PORT = 5678;
const N8N_PATH = '/webhook/blogartikel';
const WORKFLOW_ID = 'kTy9n74V2kWvLMMM';
const DB_CONTAINER = 'n8n-db-qmj0e07xtzyzn0rhfwh32ux4';
const LITELLM_HOST = '100.80.180.55';
const LITELLM_PORT = 4000;
const LITELLM_KEY = 'HostingLocal2024';

// In-memory job store: { id, url, submittedAt, execId, status, durationSec }
const jobs = [];
let jobCounter = 0;

// Descriptions store: execId (string) → [{ imageUrl, description }]
const descriptionsStore = new Map();

// Simple query via -c flag
function dbQuery(sql) {
  return new Promise((resolve) => {
    exec(`docker exec ${DB_CONTAINER} psql -U n8n -d n8n -t -c "${sql.replace(/"/g, '\\"')}"`,
      (err, stdout) => resolve(err ? '' : stdout.trim())
    );
  });
}

// Complex query via temp SQL file (avoids shell escaping issues)
function dbQueryFile(sql) {
  return new Promise((resolve) => {
    const file = `/tmp/blogui_${Date.now()}.sql`;
    fs.writeFileSync(file, sql);
    exec(`docker exec -i ${DB_CONTAINER} psql -U n8n -d n8n -t < ${file}`, (err, stdout) => {
      fs.unlinkSync(file);
      resolve(err ? '' : stdout.trim());
    });
  });
}

// Load executions from the last 24h on startup
async function loadExistingJobs() {
  const sql = `
SELECT ee.id, ee.status,
  EXTRACT(EPOCH FROM (COALESCE(ee."stoppedAt", NOW()) - ee."startedAt"))::int AS dur,
  to_char(ee."startedAt" AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS started,
  (ed.data::jsonb)->(
    (regexp_match(ed.data::text, '"source_url":"([0-9]+)"'))[1]::int
  ) AS url
FROM execution_entity ee
LEFT JOIN execution_data ed ON ed."executionId" = ee.id
WHERE ee."workflowId" = '${WORKFLOW_ID}'
  AND ee."startedAt" > NOW() - INTERVAL '24 hours'
ORDER BY ee.id ASC;`;

  const result = await dbQueryFile(sql);
  result.split('\n').forEach(line => {
    const parts = line.split('|').map(s => s.trim());
    if (parts.length < 5) return;
    const [execId, status, dur, started, rawUrl] = parts;
    if (!execId || isNaN(parseInt(execId))) return;
    const url = rawUrl ? rawUrl.replace(/^"|"$/g, '') : '(URL onbekend)';
    const jobStatus = status === 'success' ? 'done'
      : status === 'error' ? 'error'
      : status === 'running' ? 'running' : 'queued';
    jobs.push({
      id: ++jobCounter,
      url,
      submittedAt: started ? started : new Date().toISOString(),
      execId: parseInt(execId),
      status: jobStatus,
      durationSec: parseInt(dur) || 0
    });
  });
  console.log(`Opgestart: ${jobs.length} bestaande job(s) geladen uit DB.`);
}

// Poll running jobs every 12 seconds
setInterval(async () => {
  const running = jobs.filter(j => j.status === 'running' || j.status === 'queued');
  if (!running.length) return;

  const ids = running.filter(j => j.execId).map(j => j.execId).join(',');
  if (!ids) return;

  const rows = await dbQuery(
    `SELECT id, status, EXTRACT(EPOCH FROM (COALESCE("stoppedAt",NOW()) - "startedAt"))::int AS dur FROM execution_entity WHERE id IN (${ids})`
  );
  rows.split('\n').forEach(line => {
    const parts = line.trim().split('|').map(s => s.trim());
    if (parts.length < 3) return;
    const [execId, status, dur] = parts;
    const job = jobs.find(j => String(j.execId) === String(execId));
    if (!job) return;
    if (status === 'success') { job.status = 'done'; job.durationSec = parseInt(dur); }
    else if (status === 'error') { job.status = 'error'; job.durationSec = parseInt(dur); }
    else if (status === 'running') { job.durationSec = parseInt(dur); }
  });
}, 12000);

// Assign execId to newly submitted jobs (query DB 3s after submission)
async function assignExecId(jobId) {
  await new Promise(r => setTimeout(r, 3000));
  const row = await dbQuery(
    `SELECT id FROM execution_entity WHERE "workflowId" = '${WORKFLOW_ID}' ORDER BY id DESC LIMIT 1`
  );
  const execId = parseInt(row.trim());
  const job = jobs.find(j => j.id === jobId);
  if (job && !isNaN(execId)) job.execId = execId;
}

const server = http.createServer((req, res) => {
  // GET / — serve HTML
  if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(HTML);
    return;
  }

  // GET /api/status — return job list as JSON
  if (req.method === 'GET' && req.url === '/api/status') {
    const out = jobs.slice().reverse().map(j => ({
      ...j,
      hasDescriptions: j.execId ? descriptionsStore.has(String(j.execId)) : false
    }));
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(out));
    return;
  }

  // POST /submit — forward to n8n and track
  if (req.method === 'POST' && req.url === '/submit') {
    let body = '';
    req.on('data', d => body += d);
    req.on('end', () => {
      let data;
      try { data = JSON.parse(body); } catch {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'Ongeldige JSON' }));
        return;
      }
      if (!data.source_url) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'source_url ontbreekt' }));
        return;
      }

      const job = { id: ++jobCounter, url: data.source_url, submittedAt: new Date().toISOString(), execId: null, status: 'queued', durationSec: 0 };
      jobs.push(job);

      const payload = JSON.stringify({
        source_url:    data.source_url,
        model:         data.model         || 'standaard',
        vision_model:  data.vision_model  || 'qwen2.5vl-7b',
        image_backend: data.image_backend || 'local',
        image_model:   data.image_model   || 'sdxl',
        replicate_key: data.replicate_key || ''
      });
      const proxyReq = http.request({
        hostname: N8N_HOST, port: N8N_PORT, path: N8N_PATH,
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }
      }, (proxyRes) => {
        let d = '';
        proxyRes.on('data', x => d += x);
        proxyRes.on('end', () => {
          if (proxyRes.statusCode < 400) {
            job.status = 'running';
            assignExecId(job.id);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true, jobId: job.id }));
          } else {
            job.status = 'error';
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: false, error: 'n8n: ' + d }));
          }
        });
      });
      proxyReq.on('error', e => {
        job.status = 'error';
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: e.message }));
      });
      proxyReq.setTimeout(10000, () => proxyReq.destroy(new Error('timeout')));
      proxyReq.write(payload);
      proxyReq.end();
    });
    return;
  }

  if (req.method === 'GET' && req.url === '/api/system') {
    const options = {
      hostname: '100.80.180.55', port: 11435, path: '/api/stats', method: 'GET'
    };
    const proxyReq = http.request(options, (proxyRes) => {
      let body = '';
      proxyRes.on('data', chunk => body += chunk);
      proxyRes.on('end', () => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(body);
      });
    });
    proxyReq.on('error', () => { res.writeHead(500); res.end('{}'); });
    proxyReq.end();
    return;
  }

  if (req.method === 'GET' && req.url === '/api/models') {
    const options = {
      hostname: LITELLM_HOST, port: LITELLM_PORT, path: '/models', method: 'GET',
      headers: { 'Authorization': `Bearer ${LITELLM_KEY}` }
    };
    const proxyReq = http.request(options, (proxyRes) => {
      let body = '';
      proxyRes.on('data', chunk => body += chunk);
      proxyRes.on('end', () => {
        try {
          const data = JSON.parse(body);
          const ALIASES = ['standaard', 'qwen2-vl-7b', 'qwen2.5vl-7b'];
          const models = (data.data || [])
            .map(m => m.id)
            .filter(id => !ALIASES.includes(id));
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(models));
        } catch (e) {
          res.writeHead(500); res.end('[]');
        }
      });
    });
    proxyReq.on('error', () => { res.writeHead(500); res.end('[]'); });
    proxyReq.end();
    return;
  }

  // POST /api/descriptions — n8n callback met vision omschrijvingen
  if (req.method === 'POST' && req.url === '/api/descriptions') {
    let body = '';
    req.on('data', d => body += d);
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        const execId = String(data.execId || '');
        const descs = Array.isArray(data.descriptions) ? data.descriptions : [];
        if (execId) descriptionsStore.set(execId, descs);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch {
        res.writeHead(400); res.end('{}');
      }
    });
    return;
  }

  // GET /api/descriptions/:execId — download omschrijvingen als JSON
  if (req.method === 'GET' && req.url.startsWith('/api/descriptions/')) {
    const execId = req.url.slice('/api/descriptions/'.length);
    const descs = descriptionsStore.get(execId) || [];
    const json = JSON.stringify({ execId, descriptions: descs }, null, 2);
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Content-Disposition': `attachment; filename="omschrijvingen-${execId}.json"`
    });
    res.end(json);
    return;
  }

  // GET /api/vision-models — beschikbare vision modellen
  if (req.method === 'GET' && req.url === '/api/vision-models') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(['qwen2.5vl-7b']));
    return;
  }

  if (req.method === 'GET' && req.url === '/logo.png') {
    fs.readFile('/opt/blog-ui/logo-white.png', (err, data) => {
      if (err) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'max-age=86400' });
      res.end(data);
    });
    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('Blog UI: http://0.0.0.0:' + PORT);
  loadExistingJobs();
});

// ─── HTML ────────────────────────────────────────────────────────────────────
const HTML = `<!DOCTYPE html>
<html lang="nl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Blog Convertor \u2014 Working Local</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600;700&family=Outfit:wght@400;600;700;800&display=swap" rel="stylesheet">
<style>
:root{
  --navy:#020E28;
  --navy-light:#0d1f45;
  --yellow:#FFB818;
  --yellow-dark:#d99a00;
  --yellow-light:#fff8e6;
  --danger:#e04444;
  --success:#1a9e5e;
  --warn:#f0a500;
  --text:#020E28;
  --text-muted:#5a6880;
  --border:#e2e8f0;
  --bg:#f4f6f9;
  --card:#ffffff;
  --radius:12px;
}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'DM Sans',sans-serif;background:var(--bg);color:var(--text);min-height:100vh}

/* ── Header ── */
header{background:var(--navy);color:#fff;padding:0 32px;height:68px;display:flex;align-items:center;justify-content:space-between;box-shadow:0 2px 12px rgba(2,14,40,.4)}
.header-left{display:flex;align-items:center;gap:16px}
.header-logo{height:38px;width:auto;display:block}
.header-divider{width:1px;height:28px;background:rgba(255,255,255,.2)}
.header-label{font-family:'Outfit',sans-serif;font-weight:600;font-size:1.9rem;color:rgba(255,255,255,.9);letter-spacing:-.1px}
.badge{background:var(--yellow);color:var(--navy);font-size:.63rem;padding:4px 11px;border-radius:20px;font-weight:800;letter-spacing:.4px;text-transform:uppercase}

/* ── Layout ── */
main{max-width:860px;margin:36px auto;padding:0 20px}

/* ── Card ── */
.card{background:var(--card);border-radius:var(--radius);padding:28px 32px;box-shadow:0 1px 3px rgba(2,14,40,.06),0 4px 16px rgba(2,14,40,.06);margin-bottom:24px;border:1px solid var(--border)}
.card-title{font-family:'Outfit',sans-serif;font-size:.68rem;font-weight:800;color:var(--navy);text-transform:uppercase;letter-spacing:1.1px;margin-bottom:20px;display:flex;align-items:center;gap:8px}
.card-title::before{content:'';display:inline-block;width:3px;height:14px;background:var(--yellow);border-radius:2px}

/* ── Form ── */
label{display:block;font-size:.86rem;font-weight:600;color:var(--text);margin-bottom:9px}
.input-row{display:flex;gap:10px}
input[type=url]{flex:1;padding:11px 16px;border:1.5px solid var(--border);border-radius:9px;font-size:.94rem;font-family:'DM Sans',sans-serif;outline:none;transition:border-color .2s,box-shadow .2s;min-width:0;color:var(--text);background:#fff}
input[type=url]:focus{border-color:var(--yellow);box-shadow:0 0 0 3px rgba(255,184,24,.18)}
button#submit-btn{background:var(--yellow);color:var(--navy);border:none;padding:11px 24px;border-radius:9px;font-size:.9rem;font-weight:800;font-family:'DM Sans',sans-serif;cursor:pointer;white-space:nowrap;transition:background .2s,transform .1s;display:inline-flex;align-items:center;gap:8px}
button#submit-btn:hover:not(:disabled){background:var(--yellow-dark);transform:translateY(-1px)}
button#submit-btn:active:not(:disabled){transform:translateY(0)}
button#submit-btn:disabled{background:#c8c8c8;color:#888;cursor:not-allowed;transform:none}
.hint{font-size:.77rem;color:var(--text-muted);margin-top:9px;line-height:1.7}
#flash{margin-top:14px;padding:11px 15px;border-radius:9px;font-size:.86rem;display:none;line-height:1.5}
#flash.ok{background:#e8f7ef;color:#0a6638;border:1px solid #8dd4b0}
#flash.err{background:#fdecea;color:#b03030;border:1px solid #f0a8a8}
.model-row{display:flex;align-items:center;gap:12px;margin-bottom:16px}
.model-label{font-size:.86rem;font-weight:600;color:var(--text);white-space:nowrap}
select#model-select{padding:9px 14px;border:1.5px solid var(--border);border-radius:9px;font-size:.88rem;font-family:'DM Sans',sans-serif;color:var(--text);background:#fff;outline:none;cursor:pointer;transition:border-color .2s,box-shadow .2s;min-width:200px}
select#model-select:focus{border-color:var(--yellow);box-shadow:0 0 0 3px rgba(255,184,24,.18)}
.model-tag{font-size:.72rem;color:var(--text-muted);background:#f0f4f8;padding:3px 8px;border-radius:5px;display:inline-block}
.model-tag.hidden{display:none}
.wp-link{display:inline-flex;align-items:center;gap:6px;margin-top:16px;font-size:.81rem;color:var(--navy);text-decoration:none;padding:7px 14px;border:1.5px solid #c8d4e4;border-radius:8px;background:#eef2f8;transition:background .15s,border-color .15s;font-weight:600}
.wp-link:hover{background:#dde5f0;border-color:#a8b8d0}

/* ── Job list ── */
.job{border:1.5px solid var(--border);border-radius:10px;padding:16px 20px;margin-bottom:12px;transition:border-color .3s,box-shadow .3s}
.job:last-child{margin-bottom:0}
.job.running{border-color:var(--yellow);background:linear-gradient(135deg,#fffdf5 0%,#fff8e6 100%);box-shadow:0 2px 10px rgba(255,184,24,.15)}
.job.done{border-color:var(--success);background:linear-gradient(135deg,#f5fdfb 0%,#eaf8f3 100%)}
.job.error{border-color:var(--danger);background:#fff8f8}
.job.queued{border-color:#c8b040;background:#fffcf0}
.job-header{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:12px}
.job-url{font-family:'DM Sans',monospace;font-size:.81rem;color:var(--navy);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:520px;font-weight:500}
.job-time{font-size:.73rem;color:var(--text-muted);white-space:nowrap}
.stages{display:flex;gap:0;margin-bottom:10px}
.stage{flex:1;text-align:center;font-size:.67rem;font-weight:700;font-family:'Outfit',sans-serif;padding:5px 4px;color:#b0bec5;border-bottom:3px solid #e8edf2;transition:all .4s;position:relative;letter-spacing:.3px;text-transform:uppercase}
.stage.active{color:var(--navy);border-color:var(--yellow)}
.stage.active::after{content:'';position:absolute;bottom:-6px;left:50%;transform:translateX(-50%);width:8px;height:8px;background:var(--yellow);border-radius:50%}
.stage.done-stage{color:var(--success);border-color:var(--success)}
.stage.error-stage{color:var(--danger);border-color:var(--danger)}
.progress-wrap{height:7px;background:#e8edf2;border-radius:4px;overflow:hidden}
.progress-bar{height:100%;border-radius:4px;transition:width .6s ease,background .4s}
.progress-bar.running-bar{background:linear-gradient(90deg,var(--navy),var(--yellow),#ffd060,var(--yellow),var(--navy));background-size:200% 100%;animation:shimmer 2s linear infinite}
.progress-bar.done-bar{background:var(--success)}
.progress-bar.error-bar{background:var(--danger)}
.progress-bar.queued-bar{background:var(--yellow)}
@keyframes shimmer{0%{background-position:200% 0}100%{background-position:-200% 0}}
.job-status-text{font-size:.77rem;color:var(--text-muted);margin-top:8px}
.job-status-text.running{color:var(--navy);font-weight:600}
.job-status-text.done{color:var(--success);font-weight:600}
.job-status-text.error{color:var(--danger)}
.empty-jobs{text-align:center;color:#b0bec5;padding:32px 0;font-size:.88rem}
.dot{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:6px;vertical-align:middle;flex-shrink:0}
.dot.running{background:var(--yellow);animation:pulse 1.2s ease-in-out infinite}
.dot.done{background:var(--success)}
.dot.error{background:var(--danger)}
.dot.queued{background:var(--yellow)}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.35}}
.spinner{width:14px;height:14px;border:2px solid rgba(2,14,40,.25);border-top-color:var(--navy);border-radius:50%;animation:spin .7s linear infinite;display:inline-block}
@keyframes spin{to{transform:rotate(360deg)}}
.refresh-hint{font-size:.71rem;color:#b0bec5;text-align:right;margin-top:10px}

/* ── Image settings ── */
.settings-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:4px}
@media(max-width:600px){.settings-grid{grid-template-columns:1fr}}
.settings-label{font-size:.86rem;font-weight:600;color:var(--text);margin-bottom:7px;display:block}
select.settings-select{width:100%;padding:9px 14px;border:1.5px solid var(--border);border-radius:9px;font-size:.88rem;font-family:'DM Sans',sans-serif;color:var(--text);background:#fff;outline:none;cursor:pointer;transition:border-color .2s,box-shadow .2s}
select.settings-select:focus{border-color:var(--yellow);box-shadow:0 0 0 3px rgba(255,184,24,.18)}
.replicate-row{margin-top:12px;display:none}
.replicate-row.visible{display:block}
input.api-key-input{width:100%;padding:9px 14px;border:1.5px solid var(--border);border-radius:9px;font-size:.88rem;font-family:'DM Sans',sans-serif;color:var(--text);background:#fff;outline:none;transition:border-color .2s,box-shadow .2s}
input.api-key-input:focus{border-color:var(--yellow);box-shadow:0 0 0 3px rgba(255,184,24,.18)}
.section-divider{border:none;border-top:1.5px solid var(--border);margin:20px 0}

/* ── Stap-labels ── */
.phase-label{font-family:'Outfit',sans-serif;font-size:.72rem;font-weight:800;color:var(--navy);text-transform:uppercase;letter-spacing:.8px;margin-bottom:12px;padding:5px 10px;background:var(--yellow-light);border-left:3px solid var(--yellow);border-radius:0 6px 6px 0}
.phase-hint{font-size:.72rem;font-weight:400;color:var(--text-muted);text-transform:none;letter-spacing:0;font-family:'DM Sans',sans-serif}

/* ── Download knop ── */
.desc-download{display:inline-flex;align-items:center;gap:6px;margin-top:10px;font-size:.78rem;color:var(--navy);text-decoration:none;padding:5px 12px;border:1.5px solid #c8d4e4;border-radius:7px;background:#eef2f8;font-weight:600;transition:background .15s}
.desc-download:hover{background:#dde5f0;border-color:#a8b8d0}

/* ── Resource bars (RAM + CPU) ── */
.resource-grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}
@media(max-width:640px){.resource-grid{grid-template-columns:1fr}}

.ram-row{display:flex;align-items:center;gap:14px;margin-bottom:14px}
.ram-labels{display:flex;justify-content:space-between;font-size:.75rem;color:var(--text-muted);margin-bottom:6px}
.ram-wrap{flex:1}
.ram-track{height:14px;background:#e8edf2;border-radius:7px;overflow:hidden;position:relative}
.ram-bar{height:100%;border-radius:7px;background:linear-gradient(90deg,var(--navy),#1a3a6e);transition:width .8s ease}
.ram-bar.warn{background:linear-gradient(90deg,#c07800,#f0a500)}
.ram-bar.full{background:linear-gradient(90deg,#a02020,var(--danger))}
.ram-numbers{font-size:.82rem;font-weight:700;color:var(--navy);white-space:nowrap;min-width:80px;text-align:right}
.ram-models{display:flex;gap:6px;flex-wrap:wrap;margin-top:8px}
.ram-model-tag{font-size:.72rem;background:var(--navy);color:var(--yellow);padding:3px 9px;border-radius:5px;font-weight:600}

/* ── CPU bar ── */
.cpu-total-row{margin-bottom:12px}
.cpu-cores-grid{display:grid;grid-template-columns:repeat(10,1fr);gap:4px}
.cpu-core{display:flex;flex-direction:column;align-items:center;gap:3px}
.cpu-core-track{width:100%;height:36px;background:#e8edf2;border-radius:4px;overflow:hidden;display:flex;align-items:flex-end}
.cpu-core-bar{width:100%;border-radius:4px;transition:height .8s ease,background .4s}
.cpu-core-label{font-size:.58rem;color:var(--text-muted)}
</style>
</head>
<body>
<header>
  <div class="header-left">
    <img class="header-logo" src="/logo.png" alt="Working Local">
    <div class="header-divider"></div>
    <span class="header-label">Blog Convertor</span>
  </div>
  <span class="badge">AI &#x2022; Qwen2.5</span>
</header>
<main>
  <div class="card">
    <div class="card-title">Artikel insturen</div>

    <div class="phase-label">Stap 1 — Tekst herschrijven &amp; afbeeldingen omschrijven</div>
    <div class="settings-grid" style="margin-bottom:12px">
      <div>
        <label class="settings-label" for="model-select">Tekst&#8209;model <span class="phase-hint">(artikel herschrijven)</span></label>
        <select id="model-select" class="settings-select"><option value="standaard">Laden…</option></select>
        <div class="model-tag" id="model-tag" style="margin-top:5px"></div>
      </div>
      <div>
        <label class="settings-label" for="vision-model-select">Vision&#8209;model <span class="phase-hint">(foto&#8217;s lezen &amp; omschrijven)</span></label>
        <select id="vision-model-select" class="settings-select"><option value="qwen2.5vl-7b">Laden…</option></select>
      </div>
    </div>

    <label for="url-input">Bron-URL van het te herschrijven artikel</label>
    <div class="input-row">
      <input type="url" id="url-input" placeholder="https://voorbeeld.com/blogartikel" autocomplete="off"/>
      <button id="submit-btn" onclick="submitUrl()">
        <span id="btn-inner">&#9654; Verwerken</span>
      </button>
    </div>
    <div class="hint" id="model-hint"></div>

    <hr class="section-divider">

    <div class="phase-label">Stap 2 — Nieuwe afbeeldingen genereren</div>
    <div class="settings-grid">
      <div>
        <label class="settings-label" for="img-backend-select">Via <span class="phase-hint">(renderplatform)</span></label>
        <select id="img-backend-select" class="settings-select" onchange="onBackendChange()">
          <option value="local">Lokaal — Stable Diffusion (CPU)</option>
          <option value="replicate">Replicate API (cloud, snel)</option>
        </select>
      </div>
      <div>
        <label class="settings-label" for="img-model-select">Generatiemodel <span class="phase-hint">(diffusiemodel)</span></label>
        <select id="img-model-select" class="settings-select">
          <option value="sdxl">Stable Diffusion XL</option>
          <option value="sdxl-turbo">SDXL Turbo — sneller</option>
          <option value="sd15">Stable Diffusion 1.5 — kleinste</option>
          <option value="flux-schnell" class="replicate-only">Flux.1 Schnell (Replicate)</option>
          <option value="flux-dev" class="replicate-only">Flux.1 Dev (Replicate)</option>
        </select>
      </div>
    </div>
    <div class="replicate-row" id="replicate-row">
      <label class="settings-label" for="replicate-key-input">Replicate API-key</label>
      <input type="password" id="replicate-key-input" class="api-key-input" placeholder="r8_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" autocomplete="off"/>
    </div>

    <div id="flash"></div>
    <a class="wp-link" href="https://wordpress.workinglocal.be/wp-admin/edit.php?post_status=draft&post_type=post" target="_blank">&#8594;&nbsp;WordPress-concepten bekijken</a>
  </div>

  <div class="resource-grid">
    <div class="card">
      <div class="card-title">AI-engine geheugen</div>
      <div class="ram-wrap">
        <div class="ram-labels">
          <span id="ram-used-label">Laden…</span>
          <span id="ram-total-label"></span>
        </div>
        <div class="ram-track"><div class="ram-bar" id="ram-bar" style="width:0%"></div></div>
      </div>
      <div class="ram-models" id="ram-models"></div>
    </div>

    <div class="card">
      <div class="card-title">AI-engine CPU</div>
      <div class="cpu-total-row">
        <div class="ram-labels">
          <span id="cpu-used-label">Laden…</span>
          <span id="cpu-cores-label"></span>
        </div>
        <div class="ram-track"><div class="ram-bar" id="cpu-bar" style="width:0%"></div></div>
      </div>
      <div class="cpu-cores-grid" id="cpu-cores-grid"></div>
    </div>
  </div>

  <div class="card">
    <div class="card-title">Verwerkingsstatus</div>
    <div id="job-list"><div class="empty-jobs">Nog geen artikels ingediend.</div></div>
    <div class="refresh-hint" id="refresh-hint"></div>
  </div>
</main>

<script>
const STAGES = ['Ophalen','AI-rewrite','Afbeeldingen','WordPress'];
let lastUpdate = 0;

function fmt(iso){
  const d=new Date(iso);
  return d.toLocaleDateString('nl-BE',{day:'2-digit',month:'2-digit'})+' '+
         d.toLocaleTimeString('nl-BE',{hour:'2-digit',minute:'2-digit'});
}
function fmtDur(sec){
  if(!sec||sec<1) return '';
  if(sec<60) return sec+'s';
  const m=Math.floor(sec/60), s=sec%60;
  return m+'m'+(s?s+'s':'');
}

function stageForJob(job){
  if(job.status==='queued') return -1;
  if(job.status==='done') return 3;
  if(job.status==='error') return -2;
  // running: estimate from duration
  const d=job.durationSec||0;
  if(d<35) return 0;
  if(d<job.estTotal*0.95||!job.estTotal) return 1;
  return 2;
}

function progressPct(job){
  if(job.status==='queued') return 4;
  if(job.status==='done') return 100;
  if(job.status==='error') return 100;
  const d=job.durationSec||0;
  if(d<35) return 5+Math.min(d/35*8,8);  // 5-13% scraping
  // AI phase: slow fill from 14% to 88%
  const aiSec=d-35;
  const est=job.estTotal?job.estTotal-35:3200;
  return 14+Math.min(aiSec/est*74,74);
}

function renderJobs(jobs){
  const el=document.getElementById('job-list');
  if(!jobs.length){el.innerHTML='<div class="empty-jobs">Nog geen artikels ingediend.</div>';return;}
  el.innerHTML=jobs.map(job=>{
    const stage=stageForJob(job);
    const pct=progressPct(job);
    const barCls=job.status==='done'?'done-bar':job.status==='error'?'error-bar':job.status==='queued'?'queued-bar':'running-bar';
    const stageHtml=STAGES.map((s,i)=>{
      let cls='';
      if(job.status==='error') cls='error-stage';
      else if(job.status==='done') cls='done-stage';
      else if(i===stage) cls='active';
      else if(i<stage) cls='done-stage';
      return '<div class="stage '+cls+'">'+s+'</div>';
    }).join('');
    const dur=job.durationSec>0?' &mdash; '+fmtDur(job.durationSec):'';
    let statusText='', statusCls='';
    if(job.status==='queued'){statusText='In wachtrij\u2026';statusCls='';}
    else if(job.status==='running'&&stage===0){statusText='Artikel ophalen via Jina.ai\u2026';statusCls='running';}
    else if(job.status==='running'&&stage===1){statusText='AI verwerkt de tekst (Qwen2.5-72b)\u2026'+dur;statusCls='running';}
    else if(job.status==='running'&&stage===2){statusText='Concept opslaan in WordPress\u2026';statusCls='running';}
    else if(job.status==='done'){statusText='&#10003; Concept aangemaakt in WordPress'+dur;statusCls='done';}
    else if(job.status==='error'){statusText='&#10007; Fout bij verwerking'+dur;statusCls='error';}
    const dlBtn = job.hasDescriptions && job.execId
      ? '<a class="desc-download" href="/api/descriptions/'+job.execId+'" download>&#8659; Afbeeldingsomschrijvingen (JSON)</a>'
      : '';
    return '<div class="job '+job.status+'">'
      +'<div class="job-header">'
      +'<span class="dot '+job.status+'"></span><span class="job-url" title="'+job.url+'">'+job.url+'</span>'
      +'<span class="job-time">'+fmt(job.submittedAt)+'</span>'
      +'</div>'
      +'<div class="stages">'+stageHtml+'</div>'
      +'<div class="progress-wrap"><div class="progress-bar '+barCls+'" style="width:'+pct+'%"></div></div>'
      +'<div class="job-status-text '+statusCls+'">'+statusText+'</div>'
      +dlBtn
      +'</div>';
  }).join('');
}

async function poll(){
  try{
    const r=await fetch('/api/status');
    const jobs=await r.json();
    renderJobs(jobs);
    lastUpdate=Date.now();
    const hasRunning=jobs.some(j=>j.status==='running'||j.status==='queued');
    document.getElementById('refresh-hint').textContent=hasRunning?'Automatisch bijgewerkt elke 12 seconden':'';
  }catch(e){}
}

function submitUrl(){
  const input=document.getElementById('url-input');
  const url=input.value.trim();
  if(!url.startsWith('http')){showFlash('Geef een geldige URL in die begint met http.','err');return;}
  const btn=document.getElementById('submit-btn');
  const inner=document.getElementById('btn-inner');
  btn.disabled=true;
  inner.innerHTML='<span class="spinner"></span> Doorsturen\u2026';
  showFlash('Artikel wordt doorgestuurd\u2026','');
  const model        = document.getElementById('model-select').value||'standaard';
  const visionModel  = document.getElementById('vision-model-select').value||'qwen2.5vl-7b';
  const imageBackend = document.getElementById('img-backend-select').value||'local';
  const imageModel   = document.getElementById('img-model-select').value||'sdxl';
  const replicateKey = document.getElementById('replicate-key-input').value.trim();
  if(imageBackend==='replicate'&&!replicateKey){showFlash('Geef een Replicate API-key in.','err');return;}
  fetch('/submit',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({source_url:url,model:model,vision_model:visionModel,image_backend:imageBackend,image_model:imageModel,replicate_key:replicateKey})})
    .then(r=>r.json())
    .then(d=>{
      if(d.ok){
        showFlash('Ingediend. De AI verwerkt het op de achtergrond \u2014 controleer de voortgang hieronder.','ok');
        input.value='';
        poll();
      } else {
        showFlash('Fout: '+(d.error||'onbekend'),'err');
      }
    })
    .catch(e=>showFlash('Verbindingsfout: '+e.message,'err'))
    .finally(()=>{btn.disabled=false;inner.innerHTML='&#9654; Verwerken';});
}

function showFlash(msg,type){
  const el=document.getElementById('flash');
  el.innerHTML=msg;
  el.className=type||'info';
  el.style.display=msg?'block':'none';
}

document.getElementById('url-input').addEventListener('keydown',e=>{if(e.key==='Enter')submitUrl();});

async function loadModels(){
  try{
    const models=await fetch('/api/models').then(r=>r.json());
    const sel=document.getElementById('model-select');
    const tag=document.getElementById('model-tag');
    if(!models.length){sel.innerHTML='<option value="standaard">standaard</option>';return;}
    sel.innerHTML=models.map(m=>'<option value="'+m+'">'+m+'</option>').join('');
    const MODEL_INFO = {
      '72b':  { tag: '~47 GB · traag',  tijd: '30–90 min',  label: 'Qwen2.5-72b' },
      '70b':  { tag: '~43 GB · traag',  tijd: '30–90 min',  label: 'Llama3.3-70b' },
      '32b':  { tag: '~20 GB · middel', tijd: '10–25 min',  label: 'Qwen2.5-32b' },
      '14b':  { tag: '~9 GB · middel',  tijd: '5–10 min',   label: 'Qwen2.5-14b' },
      '7b':   { tag: '~5 GB · snel',    tijd: '2–5 min',    label: 'Qwen2.5-7b' },
      '8b':   { tag: '~5 GB · snel',    tijd: '2–5 min',    label: 'Llama3.2-8b' },
    };
    const updateTag=()=>{
      const v=sel.value;
      const key=Object.keys(MODEL_INFO).find(k=>v.includes(k))||null;
      const info=key?MODEL_INFO[key]:{tag:'',tijd:null,label:v};
      tag.textContent=info.tag;
      tag.className='model-tag'+(info.tag?'':' hidden');
      const hint=document.getElementById('model-hint');
      const tijdStr=info.tijd?' Verwerking duurt doorgaans '+info.tijd+'.':'';
      hint.textContent='Het artikel wordt opgehaald via Jina.ai, herschreven in het Nederlands door '+info.label+' en als concept opgeslagen in WordPress.'+tijdStr+' Je kan meerdere artikelen tegelijk indienen \u2014 ze worden parallel verwerkt.';
    };
    sel.addEventListener('change',updateTag);
    updateTag();
  }catch(e){}
}

function barColor(pct){return pct>=90?' full':pct>=70?' warn':'';}

async function pollSystem(){
  try{
    const d=await fetch('/api/system').then(r=>r.json());

    // RAM
    const ramPct=Math.round(d.used_gb/d.total_gb*100);
    const ramBar=document.getElementById('ram-bar');
    ramBar.style.width=ramPct+'%';
    ramBar.className='ram-bar'+barColor(ramPct);
    document.getElementById('ram-used-label').textContent=d.used_gb+' GB gebruikt ('+ramPct+'%)';
    document.getElementById('ram-total-label').textContent=d.total_gb+' GB totaal';
    const mc=document.getElementById('ram-models');
    mc.innerHTML=(d.models||[]).map(m=>'<span class="ram-model-tag">'+m.name+' \u2014 '+m.size_gb+' GB</span>').join('')
      ||'<span style="font-size:.75rem;color:#b0bec5">Geen modellen actief in geheugen</span>';

    // CPU totaal
    const cpuPct=Math.round(d.cpu_pct||0);
    const cpuBar=document.getElementById('cpu-bar');
    cpuBar.style.width=cpuPct+'%';
    cpuBar.className='ram-bar'+barColor(cpuPct);
    document.getElementById('cpu-used-label').textContent=cpuPct+'% bezet';
    document.getElementById('cpu-cores-label').textContent=(d.cpu_cores||0)+' vCPU\u2019s';

    // Per-core grid
    const cores=d.cpu_per_core||[];
    const grid=document.getElementById('cpu-cores-grid');
    grid.innerHTML=cores.map((pct,i)=>{
      const h=Math.max(3,Math.round(pct/100*36));
      const col=pct>=90?'var(--danger)':pct>=70?'var(--warn)':'var(--navy)';
      return '<div class="cpu-core">'
        +'<div class="cpu-core-track"><div class="cpu-core-bar" style="height:'+h+'px;background:'+col+'"></div></div>'
        +'<span class="cpu-core-label">'+(i+1)+'</span>'
        +'</div>';
    }).join('');
  }catch(e){}
}

function onBackendChange(){
  // Flux-opties zijn alleen beschikbaar via Replicate
  const v=document.getElementById('img-backend-select').value;
  const row=document.getElementById('replicate-row');
  const modelSel=document.getElementById('img-model-select');
  row.className='replicate-row'+(v==='replicate'?' visible':'');
  // Flux only available on Replicate
  const fluxOpts=modelSel.querySelectorAll('option[value^="flux"]');
  fluxOpts.forEach(o=>o.disabled=(v==='local'));
  if(v==='local' && modelSel.value.startsWith('flux')) modelSel.value='sdxl';
}
onBackendChange();

async function loadVisionModels(){
  try{
    const models=await fetch('/api/vision-models').then(r=>r.json());
    const sel=document.getElementById('vision-model-select');
    if(models.length){
      sel.innerHTML=models.map(m=>'<option value="'+m+'">'+m+'</option>').join('');
    }
  }catch(e){}
}

loadModels();
loadVisionModels();
pollSystem();
setInterval(pollSystem, 30000);
poll();
setInterval(poll,12000);
</script>
</body>
</html>`;
