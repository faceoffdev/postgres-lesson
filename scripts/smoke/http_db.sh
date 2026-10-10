#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://localhost:8080"
PG="docker compose exec -T pg psql -U user -d orders"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
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

request() {
  local method="$1"
  local path="$2"
  shift 2
  echo -e "  ${DIM}${method} ${BASE_URL}${path}${RESET}" >&2
  curl -fsS -X "$method" "${BASE_URL}${path}" "$@"
}

db_query() {
  local sql="$1"
  echo -e "  ${DIM}psql: ${sql}${RESET}" >&2
  $PG -t -c "$sql" 2>/dev/null | tr -d ' '
}

print_json() {
  echo -e "${DIM}$(echo "$1" | python3 -m json.tool 2>/dev/null || echo "$1")${RESET}"
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

# ─── Подготовка БД ────────────────────────────────────────────────────────────
section "Подготовка — сброс таблицы parts"
echo -e "  ${DIM}TRUNCATE parts${RESET}"
$PG -c "TRUNCATE parts;" >/dev/null
check "таблица очищена" "[ \"$(db_query 'SELECT COUNT(*) FROM parts;')\" = '0' ]"

# ─── Health Check ─────────────────────────────────────────────────────────────
section "GET /healthz — проверка доступности"
HEALTH=$(request GET /healthz)
echo -e "  ${DIM}Ответ: ${HEALTH}${RESET}"
check "возвращает 'ok'" "echo '$HEALTH' | grep -x 'ok'"

# ─── Create Parts ─────────────────────────────────────────────────────────────
section "POST /parts — создание деталей"

PART1=$(request POST /parts \
  -H 'Content-Type: application/json' \
  -d '{"name":"engine","quantity":100,"price":150000}')
ID1=$(echo "$PART1" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo -e "  Деталь 1 (id=${ID1}):"; print_json "$PART1"
check "деталь 1 имеет UUID id"          "echo '$ID1' | grep -E '^[0-9a-f-]{36}$'"
check "деталь 1 имеет name=engine"      "echo '$PART1' | grep '\"name\":\"engine\"'"
check "деталь 1 имеет quantity=100"     "echo '$PART1' | grep '\"quantity\":100'"
check "деталь 1 имеет price=150000"     "echo '$PART1' | grep '\"price\":150000'"
DB_ROW1=$(db_query "SELECT COUNT(*) FROM parts WHERE id='${ID1}' AND name='engine';")
check "деталь 1 сохранена в БД"         "[ '$DB_ROW1' = '1' ]"

PART2=$(request POST /parts \
  -H 'Content-Type: application/json' \
  -d '{"name":"gearbox","quantity":50,"price":80000}')
ID2=$(echo "$PART2" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo -e "  Деталь 2 (id=${ID2}):"; print_json "$PART2"
check "деталь 2 имеет UUID id"          "echo '$ID2' | grep -E '^[0-9a-f-]{36}$'"
check "деталь 2 имеет name=gearbox"     "echo '$PART2' | grep '\"name\":\"gearbox\"'"
DB_ROW2=$(db_query "SELECT COUNT(*) FROM parts WHERE id='${ID2}' AND name='gearbox';")
check "деталь 2 сохранена в БД"         "[ '$DB_ROW2' = '1' ]"

PART3=$(request POST /parts \
  -H 'Content-Type: application/json' \
  -d '{"name":"wheel","quantity":200,"price":12000}')
ID3=$(echo "$PART3" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo -e "  Деталь 3 (id=${ID3}):"; print_json "$PART3"
check "деталь 3 имеет UUID id"          "echo '$ID3' | grep -E '^[0-9a-f-]{36}$'"
check "деталь 3 имеет name=wheel"       "echo '$PART3' | grep '\"name\":\"wheel\"'"
DB_ROW3=$(db_query "SELECT COUNT(*) FROM parts WHERE id='${ID3}' AND name='wheel';")
check "деталь 3 сохранена в БД"         "[ '$DB_ROW3' = '1' ]"

DB_COUNT=$(db_query "SELECT COUNT(*) FROM parts;")
check "в БД ровно 3 записи"             "[ '$DB_COUNT' = '3' ]"

# ─── Get Part by ID ───────────────────────────────────────────────────────────
section "GET /parts/{id} — получение по id"

GET1=$(request GET /parts/${ID1})
echo -e "  GET /parts/${ID1}:"; print_json "$GET1"
check "возвращает engine по id=${ID1}"  "echo '$GET1' | grep '\"name\":\"engine\"'"
check "поле id совпадает"               "echo '$GET1' | grep '\"id\":\"${ID1}\"'"

GET2=$(request GET /parts/${ID2})
echo -e "  GET /parts/${ID2}:"; print_json "$GET2"
check "возвращает gearbox по id=${ID2}" "echo '$GET2' | grep '\"name\":\"gearbox\"'"

GET3=$(request GET /parts/${ID3})
echo -e "  GET /parts/${ID3}:"; print_json "$GET3"
check "возвращает wheel по id=${ID3}"   "echo '$GET3' | grep '\"name\":\"wheel\"'"

# ─── Get by non-existent ID ───────────────────────────────────────────────────
section "GET /parts/{id} — несуществующий id"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/parts/00000000-0000-0000-0000-000000000000")
echo -e "  GET /parts/00000000-...  →  HTTP ${HTTP_STATUS}"
check "возвращает 404 для отсутствующей детали" "[ '$HTTP_STATUS' = '404' ]"

# ─── List Parts ───────────────────────────────────────────────────────────────
section "GET /parts — список всех деталей"

LIST=$(request GET /parts)
echo -e "  Ответ:"; print_json "$LIST"
check "список содержит engine"          "echo '$LIST' | grep '\"name\":\"engine\"'"
check "список содержит gearbox"         "echo '$LIST' | grep '\"name\":\"gearbox\"'"
check "список содержит wheel"           "echo '$LIST' | grep '\"name\":\"wheel\"'"
check "список содержит ровно 3 элемента" "echo '$LIST' | python3 -c \"import sys,json; d=json.load(sys.stdin); exit(0 if len(d)==3 else 1)\""

# ─── Validation: bad JSON ─────────────────────────────────────────────────────
section "POST /parts — невалидный запрос"

BAD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/parts" \
  -H 'Content-Type: application/json' \
  -d 'not-json')
echo -e "  POST /parts (невалидный JSON)  →  HTTP ${BAD_STATUS}"
check "возвращает 400 для невалидного JSON" "[ '$BAD_STATUS' = '400' ]"
DB_COUNT_AFTER=$(db_query "SELECT COUNT(*) FROM parts;")
check "невалидный запрос не добавил запись в БД" "[ '$DB_COUNT_AFTER' = '3' ]"

# ─── Summary ──────────────────────────────────────────────────────────────────
summary
