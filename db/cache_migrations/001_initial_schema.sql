CREATE TABLE IF NOT EXISTS books (
  source_sha TEXT PRIMARY KEY,
  source_path TEXT,
  source_mtime REAL,
  payload_version INTEGER NOT NULL,
  generated_at REAL NOT NULL,
  title TEXT,
  language TEXT,
  authors_json TEXT,
  metadata_json TEXT,
  opf_path TEXT,
  spine_json TEXT,
  chapter_hrefs_json TEXT,
  toc_json TEXT,
  container_path TEXT,
  container_xml TEXT,
  cache_version INTEGER NOT NULL,
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS chapters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_sha TEXT NOT NULL REFERENCES books(source_sha) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  number TEXT,
  title TEXT,
  lines_json TEXT,
  metadata_json TEXT,
  blocks_json TEXT,
  raw_content TEXT,
  UNIQUE(source_sha, position)
);

CREATE TABLE IF NOT EXISTS resources (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_sha TEXT NOT NULL REFERENCES books(source_sha) ON DELETE CASCADE,
  path TEXT NOT NULL,
  data BLOB NOT NULL,
  UNIQUE(source_sha, path)
);

CREATE TABLE IF NOT EXISTS layouts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_sha TEXT NOT NULL REFERENCES books(source_sha) ON DELETE CASCADE,
  key TEXT NOT NULL,
  version INTEGER NOT NULL,
  payload_json TEXT NOT NULL,
  updated_at REAL NOT NULL,
  UNIQUE(source_sha, key)
);

CREATE TABLE IF NOT EXISTS stats (
  source_sha TEXT PRIMARY KEY REFERENCES books(source_sha) ON DELETE CASCADE,
  last_accessed REAL,
  cache_size_bytes INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_chapters_source ON chapters(source_sha, position);
CREATE INDEX IF NOT EXISTS idx_resources_source ON resources(source_sha);
CREATE INDEX IF NOT EXISTS idx_layouts_source ON layouts(source_sha, key);
