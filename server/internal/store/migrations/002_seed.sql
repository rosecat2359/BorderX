INSERT INTO admins (username, password_hash, role)
VALUES ('admin', '$2a$12$LJ3m4ys3GZfnYMz8kVsKaOm0LPTs4mNxHDqAsKvJGDqXMsEqhKfKe', 'super')
ON CONFLICT DO NOTHING;
-- 默认密码: admin123

INSERT INTO plans (name, price_cents, duration_days, traffic_limit_gb, max_devices, sort_order) VALUES
    ('入门月付', 1990, 30, 50, 2, 1),
    ('标准季付', 4990, 90, 200, 3, 2),
    ('旗舰年付', 14990, 365, 1000, 5, 3)
ON CONFLICT DO NOTHING;
