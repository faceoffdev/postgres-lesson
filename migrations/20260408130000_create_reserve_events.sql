-- +goose Up
CREATE TABLE reserve_events
(
    id         TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    part_id    TEXT        NOT NULL REFERENCES parts (id),
    quantity   INTEGER     NOT NULL CHECK (quantity > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- +goose Down
DROP TABLE reserve_events;
