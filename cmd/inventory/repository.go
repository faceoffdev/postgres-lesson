package main

import (
	"context"
	"errors"

	sq "github.com/Masterminds/squirrel"
	trmpgx "github.com/avito-tech/go-transaction-manager/drivers/pgxv5/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	psql            = sq.StatementBuilder.PlaceholderFormat(sq.Dollar)
	errPartNotFound = errors.New("деталь не найдена")
)

const (
	partsTableName      = "parts"
	partColumnID        = "id"
	partColumnName      = "name"
	partColumnQuantity  = "quantity"
	partColumnPrice     = "price"
	partColumnReserved  = "reserved"
	partColumnDesc      = "description"
	partColumnCreatedAt = "created_at"
)

type partRepository struct {
	db        *pgxpool.Pool
	ctxGetter *trmpgx.CtxGetter
}

func newPartRepository(db *pgxpool.Pool) *partRepository {
	return &partRepository{
		db:        db,
		ctxGetter: trmpgx.DefaultCtxGetter,
	}
}

func (r *partRepository) Create(ctx context.Context, req CreatePartRequest) (Part, error) {
	query, args, err := psql.
		Insert(partsTableName).
		Columns(partColumnName, partColumnQuantity, partColumnPrice, partColumnReserved, partColumnDesc).
		Values(req.Name, req.Quantity, req.Price, 0, req.Description).
		Suffix("RETURNING " + partColumnID + ", " + partColumnCreatedAt).
		ToSql()
	if err != nil {
		return Part{}, err
	}

	part := Part{
		Name:        req.Name,
		Quantity:    req.Quantity,
		Price:       req.Price,
		Reserved:    0,
		Description: req.Description,
	}

	err = r.ctxGetter.DefaultTrOrDB(ctx, r.db).QueryRow(ctx, query, args...).Scan(
		&part.ID,
		&part.CreatedAt,
	)
	if err != nil {
		return Part{}, err
	}

	return part, nil
}

func (r *partRepository) GetByID(ctx context.Context, id string) (Part, error) {
	return r.getByID(ctx, id, false)
}

func (r *partRepository) GetByIDForUpdate(ctx context.Context, id string) (Part, error) {
	return r.getByID(ctx, id, true)
}

func (r *partRepository) getByID(ctx context.Context, id string, forUpdate bool) (Part, error) {
	builder := psql.
		Select(
			partColumnID,
			partColumnName,
			partColumnQuantity,
			partColumnPrice,
			partColumnReserved,
			partColumnDesc,
			partColumnCreatedAt,
		).
		From(partsTableName).
		Where(sq.Eq{partColumnID: id})

	if forUpdate {
		builder = builder.Suffix("FOR UPDATE")
	}

	query, args, err := builder.ToSql()
	if err != nil {
		return Part{}, err
	}

	var part Part
	err = r.ctxGetter.DefaultTrOrDB(ctx, r.db).QueryRow(ctx, query, args...).Scan(
		&part.ID,
		&part.Name,
		&part.Quantity,
		&part.Price,
		&part.Reserved,
		&part.Description,
		&part.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Part{}, errPartNotFound
		}

		return Part{}, err
	}

	return part, nil
}

func (r *partRepository) List(ctx context.Context, params ListPartsParams) ([]Part, error) {
	builder := psql.
		Select(
			partColumnID,
			partColumnName,
			partColumnQuantity,
			partColumnPrice,
			partColumnReserved,
			partColumnDesc,
			partColumnCreatedAt,
		).
		From(partsTableName).
		OrderBy(partColumnID + " ASC").
		Limit(params.Limit).
		Offset(params.Offset)

	if params.Name != "" {
		builder = builder.Where(sq.Eq{partColumnName: params.Name})
	}

	if params.MinPrice != nil {
		builder = builder.Where(sq.GtOrEq{partColumnPrice: *params.MinPrice})
	}

	query, args, err := builder.ToSql()
	if err != nil {
		return nil, err
	}

	rows, err := r.ctxGetter.DefaultTrOrDB(ctx, r.db).Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var parts []Part
	for rows.Next() {
		var part Part
		if err = rows.Scan(
			&part.ID,
			&part.Name,
			&part.Quantity,
			&part.Price,
			&part.Reserved,
			&part.Description,
			&part.CreatedAt,
		); err != nil {
			return nil, err
		}

		parts = append(parts, part)
	}

	if err = rows.Err(); err != nil {
		return nil, err
	}

	return parts, nil
}

func (r *partRepository) LogReserveEvent(ctx context.Context, partID string, qty int32) error {
	_, err := r.ctxGetter.DefaultTrOrDB(ctx, r.db).Exec(
		ctx,
		`INSERT INTO reserve_events (part_id, quantity) VALUES ($1, $2)`,
		partID,
		qty,
	)
	if err != nil {
		return err
	}

	return nil
}

func (r *partRepository) IncrementReserved(ctx context.Context, id string, qty int32) error {
	tag, err := r.ctxGetter.DefaultTrOrDB(ctx, r.db).Exec(
		ctx,
		`UPDATE parts SET reserved = reserved + $1 WHERE id = $2`,
		qty,
		id,
	)
	if err != nil {
		return err
	}

	if tag.RowsAffected() == 0 {
		return errPartNotFound
	}

	return nil
}
