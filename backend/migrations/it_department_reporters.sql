-- ============================================
-- IT Department Reporters
-- Maps IT/Support departments to their reporter departments
-- ============================================

-- Table to map IT departments to their reporter departments
CREATE TABLE IF NOT EXISTS it_department_reporters (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    it_department text NOT NULL,
    reporter_department text NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE(it_department, reporter_department)
);

-- Add column to employees to mark IT team
ALTER TABLE employees ADD COLUMN IF NOT EXISTS it_team text;

-- Example data: AFTN handles issues from Operations, ATC, Finance, NOTAM
INSERT INTO it_department_reporters (it_department, reporter_department) VALUES
    ('AFTN', 'Operations'),
    ('AFTN', 'ATC'),
    ('AFTN', 'Finance'),
    ('AFTN', 'NOTAM'),
    ('Network', 'Server Room'),
    ('Network', 'Data Center')
ON CONFLICT (it_department, reporter_department) DO NOTHING;

-- Mark existing IT employees with it_team
UPDATE employees SET it_team = 'AFTN' WHERE department = 'AFTN' AND it_team IS NULL;
