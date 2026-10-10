package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"sync"
)

const (
	baseURL    = "http://localhost:8080"
	goroutines = 50
	reserveQty = 8
	partQty    = 10
)

type part struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Quantity int32  `json:"quantity"`
	Reserved int32  `json:"reserved"`
}

type reserveReq struct {
	ID       string `json:"id"`
	Quantity int32  `json:"quantity"`
}

func main() {
	fmt.Println("═══════════════════════════════════════")
	fmt.Println("  Демо: race condition при резервировании")
	fmt.Println("═══════════════════════════════════════")
	fmt.Println()

	// 1. Создаём деталь
	fmt.Printf("Создаём деталь с quantity=%d ...\n", partQty)
	body, _ := json.Marshal(map[string]any{
		"name":     "Race-тест",
		"quantity": partQty,
		"price":    1000,
	})
	resp, err := http.Post(baseURL+"/parts", "application/json", bytes.NewReader(body))
	if err != nil {
		fmt.Println("Ошибка создания детали:", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	var created part
	json.NewDecoder(resp.Body).Decode(&created)
	fmt.Printf("Создана: id=%s, quantity=%d, reserved=%d\n\n", created.ID, created.Quantity, created.Reserved)

	// 2. Запускаем горутины
	fmt.Printf("Запускаем %d горутин, каждая резервирует по %d (доступно %d)\n", goroutines, reserveQty, partQty)
	fmt.Println("Максимум должна пройти 1 горутина, остальные — отказ.")
	fmt.Println()

	var wg sync.WaitGroup
	start := make(chan struct{}) // барьер — все стартуют одновременно

	results := make([]int, goroutines)

	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()

			reqBody, _ := json.Marshal(reserveReq{
				ID:       created.ID,
				Quantity: reserveQty,
			})

			<-start // ждём сигнала

			r, err := http.Post(baseURL+"/parts/reserve", "application/json", bytes.NewReader(reqBody))
			if err != nil {
				results[idx] = -1
				return
			}
			io.Copy(io.Discard, r.Body)
			r.Body.Close()
			results[idx] = r.StatusCode
		}(i)
	}

	// Все горутины готовы — стреляем
	close(start)
	wg.Wait()

	// 3. Считаем результаты
	ok := 0
	conflict := 0
	other := 0
	for _, code := range results {
		switch code {
		case 204:
			ok++
		case 409:
			conflict++
		default:
			other++
		}
	}

	fmt.Printf("Результаты: 204 (успех)=%d, 409 (отказ)=%d, другое=%d\n\n", ok, conflict, other)

	// 4. Проверяем состояние через API
	resp2, err := http.Get(fmt.Sprintf("%s/parts/%s", baseURL, created.ID))
	if err != nil {
		fmt.Println("Ошибка получения детали:", err)
		os.Exit(1)
	}
	defer resp2.Body.Close()

	var current part
	json.NewDecoder(resp2.Body).Decode(&current)

	fmt.Println("═══════════════════════════════════════")
	fmt.Printf("  quantity = %d\n", current.Quantity)
	fmt.Printf("  reserved = %d\n", current.Reserved)
	fmt.Println("═══════════════════════════════════════")

	if current.Reserved > current.Quantity {
		fmt.Println()
		fmt.Printf("⚠ ПРОБЛЕМА: reserved (%d) > quantity (%d)\n", current.Reserved, current.Quantity)
		fmt.Printf("  %d горутин прошли проверку, хотя хватает максимум на %d\n", ok, current.Quantity/int32(reserveQty))
		fmt.Println("  Причина: SELECT и UPDATE не в одной транзакции.")
		fmt.Println()
		os.Exit(1)
	} else if ok > 1 {
		fmt.Println()
		fmt.Printf("⚠ ПРОБЛЕМА: %d горутин прошли, reserved=%d\n", ok, current.Reserved)
		fmt.Println("  Несколько запросов прошли проверку одновременно.")
		os.Exit(1)
	} else {
		fmt.Println()
		fmt.Println("✓ Гонка не воспроизвелась (транзакция защищает)")
	}
}
