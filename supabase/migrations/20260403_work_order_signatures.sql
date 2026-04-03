-- Electronic signatures for closed work orders
CREATE TABLE IF NOT EXISTS work_order_signatures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  signer_email TEXT NOT NULL,
  signer_role TEXT NOT NULL CHECK (signer_role IN ('technician', 'admin')),
  signature_data TEXT NOT NULL,
  signed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  rejection_reason TEXT
);

CREATE INDEX idx_work_order_signatures_wo_id ON work_order_signatures(work_order_id);
CREATE INDEX idx_work_order_signatures_status ON work_order_signatures(status);
