CREATE TABLE IF NOT EXISTS local_diagnostics_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at INTEGER NOT NULL,
  category TEXT NOT NULL,
  event_type TEXT NOT NULL,
  run_id TEXT,
  owner TEXT,
  subject_type TEXT,
  subject_id TEXT,
  duration_ms INTEGER,
  level TEXT,
  message TEXT,
  details_json TEXT
);
