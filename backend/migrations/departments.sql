-- Departments table for dynamic department management
-- Replaces hardcoded department lists in frontend

CREATE TABLE departments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Seed with initial departments
INSERT INTO departments (name, sort_order) VALUES
  ('General', 1),
  ('Operations', 2),
  ('ATC', 3),
  ('Finance', 4),
  ('NOTAM', 5),
  ('AFTN', 6),
  ('Network', 7);

-- Create index for faster sorting
CREATE INDEX idx_departments_sort ON departments(sort_order);
