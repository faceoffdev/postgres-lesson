package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/avito-tech/go-transaction-manager/trm/v2/manager"
	"github.com/go-chi/chi/v5"
)

type inventoryApp struct {
	repo      *partRepository
	trManager *manager.Manager
}

func newInventoryApp(repo *partRepository, trManager *manager.Manager) *inventoryApp {
	return &inventoryApp{
		repo:      repo,
		trManager: trManager,
	}
}

func (a *inventoryApp) createPart(w http.ResponseWriter, r *http.Request) {
	var req CreatePartRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "невалидный JSON", http.StatusBadRequest)
		return
	}

	part, err := a.repo.Create(r.Context(), req)
	if err != nil {
		slog.Error("не удалось создать деталь", slog.Any("ошибка", err))
		http.Error(w, "не удалось создать деталь", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(part)
}

func (a *inventoryApp) getPart(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	part, err := a.repo.GetByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, errPartNotFound) {
			http.Error(w, errPartNotFound.Error(), http.StatusNotFound)
			return
		}

		slog.Error("не удалось получить деталь", slog.String("id", id), slog.Any("ошибка", err))
		http.Error(w, "не удалось получить деталь", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(part)
}

func (a *inventoryApp) listParts(w http.ResponseWriter, r *http.Request) {
	params, err := readListPartsParams(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	parts, err := a.repo.List(r.Context(), params)
	if err != nil {
		slog.Error("не удалось получить список деталей", slog.Any("ошибка", err))
		http.Error(w, "не удалось получить список деталей", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(parts)
}

func (a *inventoryApp) handleReservePart(w http.ResponseWriter, r *http.Request) {
	var req ReservePartRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "невалидный JSON", http.StatusBadRequest)
		return
	}

	if err := a.reservePart(r.Context(), req.ID, req.Quantity); err != nil {
		switch {
		case errors.Is(err, errPartNotFound):
			http.Error(w, errPartNotFound.Error(), http.StatusNotFound)
		case errors.Is(err, errInvalidReserveRequest):
			http.Error(w, err.Error(), http.StatusBadRequest)
		case errors.Is(err, errInsufficientStock):
			http.Error(w, err.Error(), http.StatusConflict)
		default:
			slog.Error("не удалось зарезервировать деталь", slog.String("id", req.ID), slog.Any("ошибка", err))
			http.Error(w, "не удалось зарезервировать деталь", http.StatusInternalServerError)
		}
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func readListPartsParams(r *http.Request) (ListPartsParams, error) {
	q := r.URL.Query()
	params := ListPartsParams{
		Name:   q.Get("name"),
		Limit:  10,
		Offset: 0,
	}

	if v := q.Get("min_price"); v != "" {
		parsed, err := strconv.ParseInt(v, 10, 64)
		if err != nil {
			return ListPartsParams{}, fmt.Errorf("невалидный min_price")
		}
		params.MinPrice = &parsed
	}

	if v := q.Get("limit"); v != "" {
		parsed, err := strconv.ParseUint(v, 10, 64)
		if err != nil {
			return ListPartsParams{}, fmt.Errorf("невалидный limit")
		}
		params.Limit = parsed
	}

	if v := q.Get("offset"); v != "" {
		parsed, err := strconv.ParseUint(v, 10, 64)
		if err != nil {
			return ListPartsParams{}, fmt.Errorf("невалидный offset")
		}
		params.Offset = parsed
	}

	return params, nil
}
