-- =============================================================
-- Recurring Inspections — Database Migration
-- =============================================================

CREATE TABLE recurring_inspections (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT NOT NULL,
    description     TEXT DEFAULT '',
    location        TEXT DEFAULT '',
    department_id   UUID NOT NULL REFERENCES departments(id),
    frequency       TEXT NOT NULL CHECK (frequency IN ('daily', 'weekly', 'monthly')),
    day_of_week     INT,          -- 0=Mon..6=Sun (for weekly)
    day_of_month    INT,          -- 1-31 (for monthly)
    start_date      DATE NOT NULL,
    end_date        DATE,         -- NULL = no end
    next_due_date   DATE NOT NULL,
    is_active       BOOLEAN DEFAULT true,
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Track which technicians are assigned to a recurring inspection
CREATE TABLE recurring_inspection_assignees (
    recurring_inspection_id UUID NOT NULL REFERENCES recurring_inspections(id) ON DELETE CASCADE,
    fixer_id                UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (recurring_inspection_id, fixer_id)
);

-- Log of auto-generated work orders from recurring inspections
CREATE TABLE recurring_inspection_logs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recurring_inspection_id UUID NOT NULL REFERENCES recurring_inspections(id) ON DELETE CASCADE,
    work_order_id           UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    generated_at            TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_recurring_inspections_next_due ON recurring_inspections(next_due_date) WHERE is_active = true;
CREATE INDEX idx_recurring_inspections_department ON recurring_inspections(department_id);
CREATE INDEX idx_recurring_inspection_logs_ri ON recurring_inspection_logs(recurring_inspection_id);
