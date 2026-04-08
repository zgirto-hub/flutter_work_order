-- Feature 031: persist letter header field formatting (whole-field).
-- Adds font_size / bold / underline columns for Reference Number, Date,
-- Recipient, and Subject fields. All nullable; legacy rows coalesce to
-- the documented defaults on read.

alter table public.generated_letters
  add column if not exists ref_font_size       numeric default 11,
  add column if not exists ref_bold            boolean default false,
  add column if not exists ref_underline       boolean default false,
  add column if not exists tarikh_font_size    numeric default 11,
  add column if not exists tarikh_bold         boolean default false,
  add column if not exists tarikh_underline    boolean default false,
  add column if not exists recipient_font_size numeric default 12,
  add column if not exists recipient_bold      boolean default false,
  add column if not exists recipient_underline boolean default false,
  add column if not exists subject_font_size   numeric default 13,
  add column if not exists subject_bold        boolean default true,
  add column if not exists subject_underline   boolean default true;
