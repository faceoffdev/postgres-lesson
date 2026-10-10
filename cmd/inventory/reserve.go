package main

import (
	"context"
	"errors"
)

var (
	errInsufficientStock     = errors.New("недостаточно остатков")
	errInvalidReserveRequest = errors.New("количество для резерва должно быть положительным")
)

func (a *inventoryApp) reservePart(ctx context.Context, id string, qty int32) error {
	if qty <= 0 {
		return errInvalidReserveRequest
	}

	return a.trManager.Do(ctx, func(ctx context.Context) error {
		part, err := a.repo.GetByIDForUpdate(ctx, id)
		if err != nil {
			return err
		}

		if part.AvailableQuantity() < qty {
			return errInsufficientStock
		}

		if err = a.repo.IncrementReserved(ctx, id, qty); err != nil {
			return err
		}

		return a.repo.LogReserveEvent(ctx, id, qty)
	})
}
