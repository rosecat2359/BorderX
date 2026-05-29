CREATE TABLE IF NOT EXISTS admin (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    username   TEXT NOT NULL DEFAULT 'admin',
    password   TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS nodes (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    host        TEXT NOT NULL,
    ssh_port    INTEGER NOT NULL DEFAULT 22,
    ssh_user    TEXT NOT NULL DEFAULT 'root',
    ssh_key     TEXT NOT NULL DEFAULT '',
    os          TEXT NOT NULL DEFAULT 'linux',
    region      TEXT NOT NULL DEFAULT '',
    is_active   INTEGER NOT NULL DEFAULT 1,
    last_seen_at TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS inbounds (
    id          TEXT PRIMARY KEY,
    node_id     TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    tag         TEXT NOT NULL,
    protocol    TEXT NOT NULL CHECK (protocol IN ('vless','vmess','trojan','shadowsocks')),
    port        INTEGER NOT NULL,
    listen      TEXT NOT NULL DEFAULT '0.0.0.0',
    settings    TEXT NOT NULL DEFAULT '{}',
    stream      TEXT NOT NULL DEFAULT '{}',
    sniffing    INTEGER NOT NULL DEFAULT 1,
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS clients (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL DEFAULT '',
    uuid        TEXT NOT NULL UNIQUE,
    password    TEXT NOT NULL DEFAULT '',
    flow        TEXT NOT NULL DEFAULT 'xtls-rprx-vision',
    total_limit INTEGER NOT NULL DEFAULT 0,
    expiry_at   TEXT,
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS client_inbounds (
    client_id  TEXT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    inbound_id TEXT NOT NULL REFERENCES inbounds(id) ON DELETE CASCADE,
    is_visible INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (client_id, inbound_id)
);

CREATE TABLE IF NOT EXISTS traffic_hourly (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    client_id  TEXT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    inbound_id TEXT NOT NULL REFERENCES inbounds(id) ON DELETE CASCADE,
    up_bytes   INTEGER NOT NULL DEFAULT 0,
    down_bytes INTEGER NOT NULL DEFAULT 0,
    hour       TEXT NOT NULL,
    UNIQUE(client_id, inbound_id, hour)
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    action     TEXT NOT NULL,
    target     TEXT NOT NULL DEFAULT '',
    detail     TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
