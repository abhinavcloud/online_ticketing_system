ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS event_type TEXT;

-- Optional: also ensure description/status/venue_id exist if your schema is still evolving
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS description TEXT;

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS venue_id UUID;

-- If you created the enum earlier and want it:
-- ALTER TABLE public.events ADD COLUMN IF NOT EXISTS status event_status NOT NULL DEFAULT 'ON_SALE';