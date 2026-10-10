#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://localhost:8080"
PG="docker compose exec -T pg psql -U user -d orders"
ID_FILE="/tmp/race_reserve_part_id.txt"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PASS=0
FAIL=0

# ─── Helpers ──────────────────────────────────────────────────────────────────
section() {
  echo ""
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════${RESET}"
  echo -e "${CYAN}${BOLD}  $1${RESET}"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════${RESET}"
}

check() {
  local description="$1"
  local expr="$2"
  if eval "$expr" &>/dev/null; then
    echo -e "  ${GREEN}✓${RESET}  ${description}"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${RESET}  ${description}"
    FAIL=$((FAIL + 1))
  fi
}

db_query() {
  local sql="$1"
  echo -e "  ${DIM}psql: ${sql}${RESET}" >&2
  $PG -t -c "$sql" 2>/dev/null | tr -d ' '
}

summary() {
  echo ""
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════${RESET}"
  local total=$((PASS + FAIL))
  if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  ВСЕ ТЕСТЫ ПРОШЛИ${RESET}  ${DIM}(${PASS}/${total})${RESET}"
  else
    echo -e "${RED}${BOLD}  ЕСТЬ УПАВШИЕ ТЕСТЫ${RESET}  ${DIM}(прошло: ${PASS}, упало: ${FAIL}, всего: ${total})${RESET}"
  fi
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════${RESET}"
  echo ""
  [ "$FAIL" -eq 0 ]
}

usage() {
  echo "Использование: $0 <команда>"
  echo ""
  echo "Команды:"
  echo "  setup   — подготовка: очистка БД, создание детали с quantity=10"
  echo "  crash   — демо частичного сбоя: UPDATE прошёл, INSERT упал"
  exit 1
}

# ─── setup ────────────────────────────────────────────────────────────────────
cmd_setup() {
  section "Подготовка — создаём деталь с quantity=10"

  $PG -c "TRUNCATE reserve_events; TRUNCATE parts CASCADE;" >/dev/null 2>&1

  PART=$(curl -fsS -X POST "${BASE_URL}/parts" \
    -H 'Content-Type: application/json' \
    -d '{"name":"Тестовый болт","quantity":10,"price":500}')
  ID=$(echo "$PART" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

  echo "$ID" > "$ID_FILE"

  echo -e "  Создана деталь: id=${ID}"
  echo ""
  echo -e "  ${BOLD}Состояние в БД:${RESET}"
  echo -e "  quantity  = 10"
  echo -e "  reserved  = 0"
  echo -e "  событий   = 0"
  echo -e "  ${YELLOW}${BOLD}Доступно для резерва: 10${RESET}"
  echo ""
  echo -e "  ${DIM}Проверьте в БД: SELECT * FROM parts WHERE id = '${ID}';${RESET}"
  echo -e "  ${DIM}Затем запустите: go run ./cmd/racedemo/${RESET}"
}

# ─── crash ────────────────────────────────────────────────────────────────────
cmd_crash() {
  if [ ! -f "$ID_FILE" ]; then
    echo -e "${RED}Сначала запустите: $0 setup${RESET}"
    exit 1
  fi
  ID=$(cat "$ID_FILE")

  section "Демо: частичный сбой — reserved обновлён, а событие не записано"
  echo -e "  ${DIM}Эмулируем сбой: удаляем таблицу reserve_events,${RESET}"
  echo -e "  ${DIM}чтобы INSERT в неё упал, а UPDATE уже выполнен.${RESET}"
  echo ""

  # Сбрасываем
  $PG -c "TRUNCATE reserve_events; UPDATE parts SET reserved = 0 WHERE id = '${ID}';" >/dev/null 2>&1

  # Удаляем таблицу событий — INSERT упадёт
  $PG -c "DROP TABLE reserve_events;" >/dev/null

  # Резервируем
  HTTP=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${BASE_URL}/parts/reserve" \
    -H 'Content-Type: application/json' \
    -d "{\"id\":\"${ID}\",\"quantity\":3}")

  echo -e "  Запрос вернул: HTTP ${HTTP}"

  RESERVED=$(db_query "SELECT reserved FROM parts WHERE id='${ID}';")
  echo -e "  ${BOLD}Состояние в БД:${RESET}"
  echo -e "  reserved        = ${RESERVED}"
  echo -e "  reserve_events  = таблица не существует"

  if [ "$RESERVED" -gt 0 ]; then
    echo ""
    echo -e "  ${RED}${BOLD}⚠ ПРОБЛЕМА: reserved=${RESERVED}, но событие не записано${RESET}"
    echo -e "  ${RED}UPDATE прошёл, а INSERT упал — данные рассинхронизированы!${RESET}"
    echo -e "  ${DIM}С транзакцией оба запроса откатились бы вместе.${RESET}"
    echo ""
    echo -e "  ${DIM}Проверьте в БД: SELECT reserved FROM parts WHERE id = '${ID}';${RESET}"
  fi

  check "запрос вернул 500 (INSERT упал)"         "[ '${HTTP}' = '500' ]"
  check "reserved > 0 (UPDATE уже выполнился)"    "[ '${RESERVED}' -gt 0 ]"
  check "данные рассинхронизированы"               "[ '${RESERVED}' -gt 0 ] && [ '${HTTP}' = '500' ]"

  # Восстанавливаем таблицу
  section "Восстановление таблицы reserve_events"
  $PG -c "
  CREATE TABLE reserve_events (
      id         TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
      part_id    TEXT        NOT NULL REFERENCES parts (id),
      quantity   INTEGER     NOT NULL CHECK (quantity > 0),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );" >/dev/null
  echo -e "  ${DIM}Таблица reserve_events восстановлена${RESET}"

  summary
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "${1:-}" in
  setup) cmd_setup ;;
  crash) cmd_crash ;;
  *)     usage ;;
esac
