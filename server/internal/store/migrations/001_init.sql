CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','disabled','deleted')),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS admins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(64) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'operator'
        CHECK (role IN ('super','operator','viewer')),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(128) NOT NULL,
    price_cents INT NOT NULL DEFAULT 0,
    duration_days INT NOT NULL,
    traffic_limit_gb INT NOT NULL DEFAULT 0,
    max_devices INT NOT NULL DEFAULT 0,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    plan_id UUID NOT NULL REFERENCES plans(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','paid','expired','cancelled')),
    amount_cents INT NOT NULL,
    paid_at TIMESTAMP,
    starts_at TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS vpn_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    order_id UUID REFERENCES orders(id),
    protocol VARCHAR(10) NOT NULL CHECK (protocol IN ('vless','vmess','trojan')),
    uuid UUID NOT NULL,
    password VARCHAR(128) NOT NULL DEFAULT '',
    settings_json JSONB NOT NULL DEFAULT '{}',
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','disabled','expired')),
    traffic_used_bytes BIGINT NOT NULL DEFAULT 0,
    traffic_limit_bytes BIGINT NOT NULL DEFAULT 0,
    expires_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS traffic_logs (
    id BIGSERIAL PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES vpn_accounts(id),
    upload_bytes BIGINT NOT NULL DEFAULT 0,
    download_bytes BIGINT NOT NULL DEFAULT 0,
    recorded_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_traffic_logs_account ON traffic_logs(account_id, recorded_at);

CREATE TABLE IF NOT EXISTS traffic_hourly (
    id BIGSERIAL PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES vpn_accounts(id),
    upload_bytes BIGINT NOT NULL DEFAULT 0,
    download_bytes BIGINT NOT NULL DEFAULT 0,
    hour TIMESTAMP NOT NULL,
    UNIQUE(account_id, hour)
);

CREATE TABLE IF NOT EXISTS nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(128) NOT NULL,
    host VARCHAR(255) NOT NULL,
    ssh_port INT NOT NULL DEFAULT 22,
    ssh_user VARCHAR(64) NOT NULL DEFAULT 'root',
    ssh_key_path VARCHAR(512) NOT NULL DEFAULT '',
    region VARCHAR(64) NOT NULL DEFAULT '',
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_seen_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sub_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    token VARCHAR(64) NOT NULL UNIQUE,
    last_accessed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    admin_id UUID REFERENCES admins(id),
    action VARCHAR(128) NOT NULL,
    target_type VARCHAR(64) NOT NULL DEFAULT '',
    target_id UUID,
    detail_json JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
