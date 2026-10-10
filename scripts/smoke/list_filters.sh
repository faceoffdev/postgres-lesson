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

count_items() {
  echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if d else 0)"
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
section "Подготовка — наполнение тестовыми данными"
echo -e "  ${DIM}TRUNCATE parts${RESET}"
$PG -c "TRUNCATE parts;" >/dev/null

# Создаём набор деталей с разными ценами и именами
request POST /parts -H 'Content-Type: application/json' \
  -d '{"name":"engine","quantity":10,"price":150000}' >/dev/null
request POST /parts -H 'Content-Type: application/json' \
  -d '{"name":"engine","quantity":5,"price":200000}' >/dev/null
request POST /parts -H 'Content-Type: application/json' \
  -d '{"name":"gearbox","quantity":20,"price":80000}' >/dev/null
request POST /parts -H 'Content-Type: application/json' \
  -d '{"name":"gearbox","quantity":3,"price":120000}' >/dev/null
request POST /parts -H 'Content-Type: application/json' \
  -d '{"name":"wheel","quantity":100,"price":12000}' >/dev/null
request POST /parts -H 'Content-Type: application/json' \
  -d '{"name":"wheel","quantity":50,"price":15000}' >/dev/null
request POST /parts -H 'Content-Type: application/json' \
  -d '{"name":"wheel","quantity":30,"price":18000}' >/dev/null

echo -e "  ${DIM}Создано 7 деталей: 2×engine, 2×gearbox, 3×wheel${RESET}"
check "все 7 деталей в БД" \
  "[ \"$($PG -t -c 'SELECT COUNT(*) FROM parts;' 2>/dev/null | tr -d ' ')\" = '7' ]"

# ─── Без фильтров ─────────────────────────────────────────────────────────────
section "GET /parts — без фильтров"

ALL=$(request GET /parts)
ALL_COUNT=$(count_items "$ALL")
echo -e "  Элементов в ответе: ${ALL_COUNT} (дефолтный limit=10)"
check "возвращает все 7 деталей"         "[ '$ALL_COUNT' = '7' ]"

# ─── Фильтр по name ───────────────────────────────────────────────────────────
section "GET /parts?name= — фильтр по названию"

ENGINE=$(request GET '/parts?name=engine')
ENGINE_COUNT=$(count_items "$ENGINE")
echo -e "  ?name=engine → ${ENGINE_COUNT} элементов:"; print_json "$ENGINE"
check "?name=engine возвращает 2 детали"         "[ '$ENGINE_COUNT' = '2' ]"
check "все результаты имеют name=engine"          "echo '$ENGINE' | python3 -c \"import sys,json; d=json.load(sys.stdin); exit(0 if all(p['name']=='engine' for p in d) else 1)\""

GEARBOX=$(request GET '/parts?name=gearbox')
GEARBOX_COUNT=$(count_items "$GEARBOX")
echo -e "  ?name=gearbox → ${GEARBOX_COUNT} элементов"
check "?name=gearbox возвращает 2 детали"         "[ '$GEARBOX_COUNT' = '2' ]"

WHEEL=$(request GET '/parts?name=wheel')
WHEEL_COUNT=$(count_items "$WHEEL")
echo -e "  ?name=wheel → ${WHEEL_COUNT} элементов"
check "?name=wheel возвращает 3 детали"           "[ '$WHEEL_COUNT' = '3' ]"

UNKNOWN=$(request GET '/parts?name=unknown')
UNKNOWN_COUNT=$(count_items "$UNKNOWN")
echo -e "  ?name=unknown → ${UNKNOWN_COUNT} элементов"
check "?name=unknown возвращает пустой список"     "[ '$UNKNOWN_COUNT' = '0' ]"

# ─── Фильтр по min_price ──────────────────────────────────────────────────────
section "GET /parts?min_price= — фильтр по минимальной цене"

# Цены: 12000, 15000, 18000, 80000, 120000, 150000, 200000
P100=$(request GET '/parts?min_price=100000')
P100_COUNT=$(count_items "$P100")
echo -e "  ?min_price=100000 → ${P100_COUNT} элементов:"; print_json "$P100"
check "?min_price=100000 возвращает 3 детали (120k,150k,200k)" "[ '$P100_COUNT' = '3' ]"
check "все результаты имеют price >= 100000" \
  "echo '$P100' | python3 -c \"import sys,json; d=json.load(sys.stdin); exit(0 if all(p['price']>=100000 for p in d) else 1)\""

P150=$(request GET '/parts?min_price=150000')
P150_COUNT=$(count_items "$P150")
echo -e "  ?min_price=150000 → ${P150_COUNT} элементов"
check "?min_price=150000 возвращает 2 детали (150k,200k)"      "[ '$P150_COUNT' = '2' ]"

P999=$(request GET '/parts?min_price=999999')
P999_COUNT=$(count_items "$P999")
echo -e "  ?min_price=999999 → ${P999_COUNT} элементов"
check "?min_price=999999 возвращает пустой список"              "[ '$P999_COUNT' = '0' ]"

# ─── Пагинация: limit ─────────────────────────────────────────────────────────
section "GET /parts?limit= — ограничение количества результатов"

L3=$(request GET '/parts?limit=3')
L3_COUNT=$(count_items "$L3")
echo -e "  ?limit=3 → ${L3_COUNT} элементов"
check "?limit=3 возвращает не более 3 деталей"    "[ '$L3_COUNT' = '3' ]"

L1=$(request GET '/parts?limit=1')
L1_COUNT=$(count_items "$L1")
echo -e "  ?limit=1 → ${L1_COUNT} элементов"
check "?limit=1 возвращает ровно 1 деталь"         "[ '$L1_COUNT' = '1' ]"

L100=$(request GET '/parts?limit=100')
L100_COUNT=$(count_items "$L100")
echo -e "  ?limit=100 → ${L100_COUNT} элементов"
check "?limit=100 возвращает все 7 деталей"        "[ '$L100_COUNT' = '7' ]"

# ─── Пагинация: offset ────────────────────────────────────────────────────────
section "GET /parts?offset= — смещение для пагинации"

O5=$(request GET '/parts?limit=100&offset=5')
O5_COUNT=$(count_items "$O5")
echo -e "  ?offset=5 → ${O5_COUNT} элементов"
check "?offset=5 пропускает первые 5, возвращает 2"  "[ '$O5_COUNT' = '2' ]"

O7=$(request GET '/parts?limit=100&offset=7')
O7_COUNT=$(count_items "$O7")
echo -e "  ?offset=7 → ${O7_COUNT} элементов"
check "?offset=7 (за пределами) возвращает пустой список" "[ '$O7_COUNT' = '0' ]"

# Постраничная навигация: 3 страницы по 3 элемента
PAGE1=$(request GET '/parts?limit=3&offset=0')
PAGE2=$(request GET '/parts?limit=3&offset=3')
PAGE3=$(request GET '/parts?limit=3&offset=6')
P1_COUNT=$(count_items "$PAGE1")
P2_COUNT=$(count_items "$PAGE2")
P3_COUNT=$(count_items "$PAGE3")
echo -e "  Пагинация limit=3: стр.1=${P1_COUNT}, стр.2=${P2_COUNT}, стр.3=${P3_COUNT}"
check "страница 1 содержит 3 элемента"               "[ '$P1_COUNT' = '3' ]"
check "страница 2 содержит 3 элемента"               "[ '$P2_COUNT' = '3' ]"
check "страница 3 содержит 1 элемент"                "[ '$P3_COUNT' = '1' ]"
check "суммарно 7 уникальных элементов по страницам" \
  "[ $((P1_COUNT + P2_COUNT + P3_COUNT)) = '7' ]"

# ─── Комбинированные фильтры ──────────────────────────────────────────────────
section "GET /parts — комбинация фильтров"

COMBO1=$(request GET '/parts?name=engine&min_price=160000')
COMBO1_COUNT=$(count_items "$COMBO1")
echo -e "  ?name=engine&min_price=160000 → ${COMBO1_COUNT} элементов:"; print_json "$COMBO1"
check "engine + min_price=160000 → 1 деталь (200k)"  "[ '$COMBO1_COUNT' = '1' ]"
check "результат имеет name=engine и price=200000" \
  "echo '$COMBO1' | python3 -c \"import sys,json; d=json.load(sys.stdin); p=d[0]; exit(0 if p['name']=='engine' and p['price']==200000 else 1)\""

COMBO2=$(request GET '/parts?name=wheel&limit=2')
COMBO2_COUNT=$(count_items "$COMBO2")
echo -e "  ?name=wheel&limit=2 → ${COMBO2_COUNT} элементов"
check "wheel + limit=2 → ровно 2 детали"              "[ '$COMBO2_COUNT' = '2' ]"
check "все результаты имеют name=wheel" \
  "echo '$COMBO2' | python3 -c \"import sys,json; d=json.load(sys.stdin); exit(0 if all(p['name']=='wheel' for p in d) else 1)\""

# ─── Невалидные параметры ─────────────────────────────────────────────────────
section "GET /parts — невалидные параметры"

BAD_PRICE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/parts?min_price=abc")
echo -e "  ?min_price=abc  →  HTTP ${BAD_PRICE}"
check "невалидный min_price возвращает 400"   "[ '$BAD_PRICE' = '400' ]"

BAD_LIMIT=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/parts?limit=-1")
echo -e "  ?limit=-1  →  HTTP ${BAD_LIMIT}"
check "отрицательный limit возвращает 400"    "[ '$BAD_LIMIT' = '400' ]"

BAD_OFFSET=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/parts?offset=abc")
echo -e "  ?offset=abc  →  HTTP ${BAD_OFFSET}"
check "невалидный offset возвращает 400"      "[ '$BAD_OFFSET' = '400' ]"

# ─── Summary ──────────────────────────────────────────────────────────────────
summary
