ALTER TABLE orders ADD COLUMN IF NOT EXISTS IF NOT EXISTS protocol VARCHAR(10) NOT NULL DEFAULT 'vless'
    CHECK (protocol IN ('vless','vmess','trojan'));
