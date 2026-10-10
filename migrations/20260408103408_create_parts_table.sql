-- +goose Up
CREATE TABLE parts
(
    id         TEXT PRIMARY KEY     DEFAULT gen_random_uuid()::TEXT,
    name       TEXT        NOT NULL,
    quantity   INTEGER     NOT NULL CHECK (quantity >= 0),
    price      BIGINT      NOT NULL CHECK (price >= 0),
    reserved   INTEGER     NOT NULL DEFAULT 0 CHECK (reserved >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- +goose Down
DROP TABLE parts;