-- Migration: Create app_settings table for AI Provider Manager
-- Feature: 063-ai-provider-manager
-- Date: 2026-04-15

-- Create app_settings table
CREATE TABLE IF NOT EXISTS public.app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by UUID REFERENCES auth.users(id)
);

-- Enable RLS
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Create policy: authenticated users can read settings
CREATE POLICY "authenticated_select_app_settings" ON public.app_settings
    FOR SELECT
    TO authenticated
    USING (true);

-- Seed rows for AI Provider Manager
INSERT INTO public.app_settings (key, value) VALUES
    ('ai_provider', 'local'),
    ('ai_providers_available', '["local","gemini"]')
ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    updated_at = NOW();