CREATE TABLE IF NOT EXISTS local_diagnostics_network_failures (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at INTEGER NOT NULL,
  host TEXT NOT NULL,
  method TEXT NOT NULL,
  url_path TEXT NOT NULL,
  status_code INTEGER,
  exception_type TEXT,
  message TEXT,
  duration_ms INTEGER,
  retryable INTEGER NOT NULL DEFAULT 0,
  details_json TEXT
);
