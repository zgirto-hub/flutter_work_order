INSERT INTO app_settings (key, value) VALUES ('ai_work_order_enabled', 'false')
ON CONFLICT (key) DO NOTHING;