# Dynamic infrastructure context (updatable, not hardcoded)

The infrastructure context block is what turns "summarize this alert" into a real risk call. It
tells the model what is normal in your network, so it can tell a PAM lockout on a honeypot from the
same alert on a production database.

The [static version](infrastructure-context-template.md) bakes that block into the workflow's Code
node. That works, but every time you add a container or change a host's role you have to edit the
workflow, and a stale map is worse than no map: the model will confidently reason about a host that
no longer exists.

This guide swaps the hardcoded block for an **updatable data store**. You change the map in one
place, and every future alert analysis reads the current version. No more editing the workflow.

## How it works

The shipped dynamic workflow ([`wazuh-ai-security-analyzer-dynamic.workflow.json`](wazuh-ai-security-analyzer-dynamic.workflow.json))
adds one node, **Load Infra Context**, between the level filter and `Extract Alert`:

```
Webhook -> Config -> IF Level Qualifies -> Load Infra Context -> Extract Alert -> LLM -> Notify
```

**The only contract:** `Load Infra Context` must output a single item shaped like
`{ "context": "Infrastructure context:\n- ..." }`. `Extract Alert` reads `.context` and drops it
into the prompt. If the store is unreachable, `Extract Alert` falls back to a short built-in summary
(edit that fallback for your own baseline), so an alert is never blocked on the store.

Three ways to back that node. Pick one.

---

## Option A: Postgres (shipped default)

Best if you already run Postgres or want the map to scale and be queryable.

1. Apply the schema:
   ```bash
   psql -d your_db -f sql/infra_context.sql
   ```
   This creates the `infra_context` table, the `infra_context_block` view (which renders the rows
   into the `context` string), and a set of EXAMPLE rows. Replace the rows with your hosts.

2. Create a read-only role and point the n8n **Postgres** credential at it (least privilege, the
   workflow reads the map but can never change it). The role grants are in the top of
   `sql/infra_context.sql`.

3. In the workflow, open **Load Infra Context** and select your Postgres credential. The query is
   already `SELECT context FROM infra_context_block;`. Done.

Update the map any time with a plain `INSERT ... ON CONFLICT` (examples are in the SQL file). Add a
host, the next alert sees it. Preview what the model will get with `SELECT context FROM infra_context_block;`.

---

## Option B: JSON file over HTTP (no database)

Best if you do not want to run a database. Host a JSON file anywhere your n8n instance can reach it
(a static file server, an object-store URL, a raw GitHub URL, a small endpoint). Edit the file, the
workflow fetches the latest on every run.

1. Start from [`examples/infra-context.json`](examples/infra-context.json) and put your hosts in it.
2. Replace the **Load Infra Context** node with an **HTTP Request** node:
   - Method `GET`, URL = where you host the file.
   - Keep `onError: continueRegularOutput` and `retryOnFail` so a fetch hiccup falls back instead of failing.
3. If your file serves a ready `context` string (as the example does), it already satisfies the
   contract, pass it straight to `Extract Alert`. If you would rather keep structured `hosts` rows,
   add the render snippet below after the HTTP node.

---

## Option C: Google Sheets (most approachable)

Best if you want a non-technical, point-and-click map. One row per host, edit it in the browser.

1. Make a sheet with columns: `name`, `ip`, `role`, `exposure`, `status`. One host per row.
   Set `status` to `live` for active hosts.
2. Replace the **Load Infra Context** node with the n8n **Google Sheets** node (operation: Get Row(s)),
   connected to your sheet.
3. Add the render snippet below (a Code node) after the Sheets node to turn the rows into the
   `{ context }` string the analyzer expects.

---

## Render snippet (for Option B structured rows or Option C)

Drop this into a **Code** node placed between your data source and `Extract Alert`. It turns a list
of host rows into the single `{ context }` string:

```javascript
// Render structured host rows -> one { context } string for the analyzer.
const rows = $input.all().map(i => i.json);
const lines = rows
  .filter(r => (r.status ?? 'live') === 'live')
  .map(r =>
    `- ${r.name}` +
    (r.ip ? ` (${r.ip})` : '') +
    (r.role ? `: ${r.role}` : '') +
    (r.exposure ? ` [${r.exposure}]` : '')
  );
return [{ json: { context: 'Infrastructure context:\n' + lines.join('\n') } }];
```

---

## Keeping the map honest (the real win)

A dynamic store only helps if it stays current. The strongest setup is to generate the store from
whatever you already treat as your source of truth (an infra doc, an inventory export, your
config-management or IaC repo) on a schedule, so the map reconciles itself instead of relying on you
to remember.

That is how the reference deployment runs it: a drift job already reconciles the documented
infrastructure against what is actually deployed, and a small sync mirrors that doc into the store on
the same schedule. Add a host, the doc gets updated, the sync pushes it, the analyzer sees it. One
place to change, and something is already watching that place.

You do not need that much machinery to start. A hand-edited Sheet or JSON file is a real upgrade
over a hardcoded block on day one. Automate the refresh when it earns it.

## Tips

- Be specific. "internal admin workstation" is weaker than "10.0.0.15, primary admin box, nightly
  cron at 03:00 UTC". The model can only use what you tell it.
- Whichever store you choose, keep the read path read-only and keep the fallback in `Extract Alert`
  accurate enough to be useful on its own.
- For multi-tenant / MSP setups, key rows by client and filter in the query (Postgres), the URL
  (HTTP), or the sheet (a `client` column) based on the alert source.
