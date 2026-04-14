-- Make rating_id nullable to allow direct admin inserts (feature 059-add-verified-answer)
ALTER TABLE validated_qa ALTER COLUMN rating_id DROP NOT NULL;