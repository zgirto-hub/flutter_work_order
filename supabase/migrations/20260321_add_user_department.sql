-- Add department_id to users table so reporters (and all users) belong to a department
ALTER TABLE users ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id);
CREATE INDEX IF NOT EXISTS idx_users_department_id ON users(department_id);
