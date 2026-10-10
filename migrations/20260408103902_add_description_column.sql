-- +goose Up
ALTER TABLE parts
    ADD COLUMN description TEXT NULL;

-- +goose Down
ALTER TABLE parts
DROP COLUMN description;
