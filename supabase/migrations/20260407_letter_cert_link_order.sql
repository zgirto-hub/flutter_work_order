-- Migration: Add letter_link_order column to payment_certificates
-- Feature: 029-link-cert-letter
-- Date: 2026-04-07
-- Description: Add ordering column for linking payment certificates to letters

ALTER TABLE payment_certificates 
    ADD COLUMN IF NOT EXISTS letter_link_order INTEGER NULL;

CREATE INDEX IF NOT EXISTS idx_payment_certificates_letter_order 
    ON payment_certificates(letter_id, letter_link_order);