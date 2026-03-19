-- IT Teams table for dynamic IT team management
-- Replaces hardcoded IT team lists in frontend

CREATE TABLE it_teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Seed with initial IT teams
INSERT INTO it_teams (name, sort_order) VALUES
  ('AFTN', 1),
  ('Network', 2),
  ('Security', 3),
  ('Other', 4);

-- Create index for faster sorting
CREATE INDEX idx_it_teams_sort ON it_teams(sort_order);
