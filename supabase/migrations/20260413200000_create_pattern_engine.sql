-- Pattern Rules Engine: pattern_rules and pattern_alerts tables
-- Created: 2026-04-13

-- pattern_rules: stores pattern detection rules (built-in and custom)
CREATE TABLE IF NOT EXISTS pattern_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    description text,
    severity text NOT NULL CHECK (severity IN ('low', 'medium', 'high')),
    detection_type text NOT NULL CHECK (detection_type IN ('recurring_fault', 'technician_recurring', 'procedure_deviation', 'seasonal_pattern', 'long_resolution', 'parts_replaced_recurrence')),
    threshold_count integer DEFAULT 3,
    threshold_days integer DEFAULT 180,
    target_field text DEFAULT 'equipment_id',
    group_by_field text,
    enabled boolean NOT NULL DEFAULT true,
    is_built_in boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- pattern_alerts: stores fired alert instances
CREATE TABLE IF NOT EXISTS pattern_alerts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id uuid NOT NULL REFERENCES pattern_rules(id) ON DELETE CASCADE,
    work_order_ids uuid[] NOT NULL,
    equipment_id text,
    system text,
    fault_type text,
    technician_id text,
    severity text NOT NULL CHECK (severity IN ('low', 'medium', 'high')),
    status text NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'acknowledged', 'resolved')),
    message text NOT NULL,
    dedup_key text,
    detected_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for pattern_alerts
CREATE INDEX IF NOT EXISTS idx_pattern_alerts_rule_id ON pattern_alerts(rule_id);
CREATE INDEX IF NOT EXISTS idx_pattern_alerts_status ON pattern_alerts(status);
CREATE INDEX IF NOT EXISTS idx_pattern_alerts_detected_at ON pattern_alerts(detected_at DESC);

-- Partial unique index for dedup_key (only applies to full-scan alerts with non-null dedup_key)
CREATE UNIQUE INDEX IF NOT EXISTS idx_pattern_alerts_dedup_key ON pattern_alerts(dedup_key) WHERE dedup_key IS NOT NULL;

-- Comments for documentation
COMMENT ON TABLE pattern_rules IS 'Pattern detection rules (built-in and custom)';
COMMENT ON TABLE pattern_alerts IS 'Fired alert instances from pattern detection';