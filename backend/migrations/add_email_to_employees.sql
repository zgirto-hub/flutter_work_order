-- Add email column to employees table for easier lookup
ALTER TABLE employees ADD COLUMN IF NOT EXISTS email TEXT;
