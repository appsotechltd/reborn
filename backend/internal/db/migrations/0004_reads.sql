-- Seen (scrolled past) and read are different: only reads count toward
-- streaks, daily goals and referral rewards.
ALTER TABLE card_views ADD COLUMN read_at timestamptz;
UPDATE card_views SET read_at = viewed_at;
