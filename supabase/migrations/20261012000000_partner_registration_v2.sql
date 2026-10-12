-- ─────────────────────────────────────────────────────────────────────────────
-- Partner registration V2: OTP tokens table + new columns on partner_applications
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. OTP tokens for WhatsApp phone verification
CREATE TABLE IF NOT EXISTS public.partner_otp_tokens (
  phone         TEXT        PRIMARY KEY,
  hash          TEXT        NOT NULL,          -- SHA-256 of the 6-digit code
  expires_at    TIMESTAMPTZ NOT NULL,
  attempts      INT         NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Tokens are short-lived; auto-purge anything older than 1 hour to keep table small.
CREATE INDEX IF NOT EXISTS idx_partner_otp_expires ON public.partner_otp_tokens (expires_at);

-- Only the edge function (service role) reads/writes this table.
ALTER TABLE public.partner_otp_tokens ENABLE ROW LEVEL SECURITY;
-- No public policies: service role bypasses RLS.

-- 2. New columns on partner_applications
ALTER TABLE public.partner_applications
  ADD COLUMN IF NOT EXISTS workshop_address   TEXT,
  ADD COLUMN IF NOT EXISTS latitude           DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude          DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS bank_name          TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_number TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_holder TEXT,
  ADD COLUMN IF NOT EXISTS wa_verified        BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS rejection_reason   TEXT,
  ADD COLUMN IF NOT EXISTS revision_notes     TEXT,
  ADD COLUMN IF NOT EXISTS reviewed_at        TIMESTAMPTZ;

-- 3. New column on partners (carry bank detail after approval)
ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS workshop_address    TEXT,
  ADD COLUMN IF NOT EXISTS latitude            DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude           DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS bank_name           TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_number TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_holder TEXT;

-- 4. Extend submit-partner-application to accept and write new fields
-- (the edge function already passes them; just need the columns to exist above)

-- 5. Grant EXECUTE on notify() to service role (idempotent)
-- notify() already exists from the notification outbox migration.
-- No extra grants needed — service role has superuser-equivalent access.
