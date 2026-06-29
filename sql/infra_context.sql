-- Infrastructure context store for the Wazuh AI Security Analyzer (dynamic variant).
--
-- One row per host/service. The view renders the rows into a single text block that the
-- workflow's "Load Infra Context" node selects and injects into the LLM prompt. Update the
-- rows in one place (by hand, a cron job, or a config-management step) and every future alert
-- analysis uses the current map. No need to edit the workflow again.
--
-- Apply (any Postgres 12+):
--   psql -d your_db -f sql/infra_context.sql
--
-- The workflow only needs SELECT on the view. Create a read-only role for it:
--   CREATE ROLE wazuh_ctx LOGIN PASSWORD 'change-me';
--   GRANT CONNECT ON DATABASE your_db TO wazuh_ctx;
--   GRANT USAGE ON SCHEMA public TO wazuh_ctx;
--   GRANT SELECT ON infra_context, infra_context_block TO wazuh_ctx;
-- Then point the n8n Postgres credential at that role. Least privilege: it can read the map,
-- never change it.

CREATE TABLE IF NOT EXISTS infra_context (
    id            BIGSERIAL PRIMARY KEY,
    host_key      TEXT        NOT NULL UNIQUE,   -- stable id for upserts, e.g. 'vector-db' or 'host:10.0.0.20'
    name          TEXT        NOT NULL,          -- display name
    ip            TEXT,                          -- optional
    role          TEXT,                          -- what this host does
    exposure      TEXT,                          -- attack-surface note (internet-facing? internal-only?)
    status        TEXT        NOT NULL DEFAULT 'live',  -- live | retired (only 'live' rows render)
    in_context    BOOLEAN     NOT NULL DEFAULT TRUE,    -- include this row in the rendered block
    sort_order    INT         NOT NULL DEFAULT 100,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Renders the live rows into one bullet block. The workflow selects the single `context` column.
CREATE OR REPLACE VIEW infra_context_block AS
SELECT
    'Infrastructure context:' || E'\n'
      || string_agg(
           '- ' || name
             || COALESCE(' (' || ip || ')', '')
             || COALESCE(': ' || role, '')
             || COALESCE(' [' || exposure || ']', ''),
           E'\n' ORDER BY sort_order, host_key
         ) AS context,
    COUNT(*)        AS n_hosts,
    MAX(updated_at) AS last_updated
FROM infra_context
WHERE status = 'live' AND in_context = TRUE;

-- ---------------------------------------------------------------------------
-- Seed rows (EXAMPLE - replace with YOUR environment). Idempotent upsert.
-- ---------------------------------------------------------------------------
INSERT INTO infra_context (host_key, name, ip, role, exposure, sort_order) VALUES
  ('cluster',     'home lab',          NULL,         '3-node cluster on a flat /24, admin over a mesh VPN', 'internal-only except where noted', 10),
  ('vector-db',   'vector-db',         '10.0.0.20',  'vector database / knowledge bases',                   'internal-only',                    20),
  ('postgres',    'postgres',          '10.0.0.21',  'application databases',                               'internal-only',                    30),
  ('automation',  'automation / n8n',  '10.0.0.22',  'workflow automation',                                 'only /webhook/* exposed via tunnel', 40),
  ('siem',        'siem / wazuh',      '10.0.0.30',  'SIEM manager, this analyzer''s source',               'internal-only',                    50),
  ('posture',     'posture',           NULL,         'active response disabled, monitoring only',           NULL,                               900)
ON CONFLICT (host_key) DO UPDATE SET
  name=EXCLUDED.name, ip=EXCLUDED.ip, role=EXCLUDED.role, exposure=EXCLUDED.exposure,
  status='live', in_context=TRUE, sort_order=EXCLUDED.sort_order, updated_at=now();

-- ---------------------------------------------------------------------------
-- Updating the map later (this is the whole point - one place, no workflow edit):
--   INSERT INTO infra_context (host_key, name, ip, role, exposure, sort_order)
--   VALUES ('new-host', 'new-host', '10.0.0.42', 'what it does', 'internal-only', 60)
--   ON CONFLICT (host_key) DO UPDATE SET
--     name=EXCLUDED.name, ip=EXCLUDED.ip, role=EXCLUDED.role,
--     exposure=EXCLUDED.exposure, sort_order=EXCLUDED.sort_order, updated_at=now();
--
-- Retire a host (it stops rendering, history kept):
--   UPDATE infra_context SET status='retired', updated_at=now() WHERE host_key='old-host';
--
-- Preview what the workflow will see:
--   SELECT context FROM infra_context_block;
-- ---------------------------------------------------------------------------
