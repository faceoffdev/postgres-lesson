package main

import (
	"context"
	"log/slog"
	"net"
	"net/http"
	"os"

	trmpgx "github.com/avito-tech/go-transaction-manager/drivers/pgxv5/v2"
	trmmanager "github.com/avito-tech/go-transaction-manager/trm/v2/manager"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	host := os.Getenv("APP_HOST")
	port := os.Getenv("APP_PORT")
	dsn := os.Getenv("PG_DSN")
	if port == "" {
		port = "8080"
	}
	if dsn == "" {
		slog.Error("переменная окружения PG_DSN обязательна")
		os.Exit(1)
	}

	addr := net.JoinHostPort(host, port)

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		slog.Error("не удалось создать пул подключений к PostgreSQL", slog.Any("ошибка", err))
		os.Exit(1)
	}
	defer pool.Close()

	if err = pool.Ping(ctx); err != nil {
		slog.Error("не удалось проверить подключение к PostgreSQL", slog.Any("ошибка", err))
		os.Exit(1)
	}

	repo := newPartRepository(pool)
	trManager, err := trmmanager.New(trmpgx.NewDefaultFactory(pool))
	if err != nil {
		slog.Error("не удалось создать менеджер транзакций", slog.Any("ошибка", err))
		os.Exit(1)
	}

	inventory := newInventoryApp(repo, trManager)

	r := chi.NewRouter()
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	r.Post("/parts", inventory.createPart)
	r.Get("/parts/{id}", inventory.getPart)
	r.Get("/parts", inventory.listParts)
	r.Post("/parts/reserve", inventory.handleReservePart)

	slog.Info("inventory service запущен", slog.String("адрес", addr))
	if err = http.ListenAndServe(addr, r); err != nil {
		slog.Error("не удалось запустить HTTP-сервер", slog.String("адрес", addr), slog.Any("ошибка", err))
		os.Exit(1)
	}
}
