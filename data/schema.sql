PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS registry_cache (
    plugin_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    version TEXT,
    author TEXT,
    summary TEXT,
    download_url TEXT,
    distribution_type TEXT,
    distribution_url TEXT,
    source_available INTEGER DEFAULT 0,
    visibility TEXT DEFAULT 'public',
    raw_json TEXT NOT NULL,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS installed_plugins (
    plugin_id TEXT PRIMARY KEY,
    folder_name TEXT NOT NULL,
    installed_version TEXT,
    status TEXT NOT NULL DEFAULT 'installed',
    installed_at TEXT DEFAULT CURRENT_TIMESTAMP,
    last_checked_at TEXT,
    metadata_json TEXT NOT NULL
);

INSERT OR IGNORE INTO installed_plugins (
    plugin_id,
    folder_name,
    installed_version,
    status,
    metadata_json
) VALUES (
    'lyrecoul.penmods',
    'PenMods',
    'main',
    'system',
    '{"id":"lyrecoul.penmods","kind":"core","name":"PenMods"}'
);

INSERT OR IGNORE INTO installed_plugins (
    plugin_id,
    folder_name,
    installed_version,
    status,
    metadata_json
) VALUES (
    'com.penmods.plugininstaller',
    'plugin_installer',
    '0.1.0',
    'system',
    '{"id":"com.penmods.plugininstaller","kind":"plugin","name":"插件安装器"}'
);

CREATE TABLE IF NOT EXISTS install_queue (
    job_id INTEGER PRIMARY KEY AUTOINCREMENT,
    plugin_id TEXT NOT NULL,
    action TEXT NOT NULL,
    download_url TEXT,
    status TEXT NOT NULL DEFAULT 'queued',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    finished_at TEXT,
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS dependency_queue (
    job_id INTEGER PRIMARY KEY AUTOINCREMENT,
    parent_plugin_id TEXT NOT NULL,
    dependency_id TEXT NOT NULL,
    required_capabilities TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    reason TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    finished_at TEXT,
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS core_updates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    core_id TEXT NOT NULL,
    target_version TEXT NOT NULL,
    package_url TEXT NOT NULL,
    target_path TEXT NOT NULL DEFAULT '/userdata/PenMods/libPenMods.so',
    strategy TEXT NOT NULL DEFAULT 'copy-restart',
    requires_restart INTEGER DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    applied_at TEXT,
    error_message TEXT
);
