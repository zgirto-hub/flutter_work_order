CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE work_order_entities (
  work_order_id uuid PRIMARY KEY REFERENCES work_orders(id) ON DELETE CASCADE,
  equipment_id text NOT NULL,
  system text,
  equipment_type text,
  fault_type text,
  fault_code text,
  action_taken text,
  procedure_followed text,
  parts_replaced text[] DEFAULT '{}',
  outcome text,
  technician_id text,
  date text,
  embedding vector(768),
  extracted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE extraction_failures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id uuid REFERENCES work_orders(id) ON DELETE CASCADE,
  error_message text NOT NULL,
  raw_response text,
  attempt_number int NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_extraction_failures_work_order_id ON extraction_failures(work_order_id);
