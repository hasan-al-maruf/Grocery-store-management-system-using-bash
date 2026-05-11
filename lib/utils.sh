#!/bin/bash

# GSMS Utility Functions
# Helper functions used across the system

source ./config/config.sh

# ==================== PASSWORD HASHING ====================

hash_password() {
    local password="$1"
    echo -n "$password" | sha256sum | awk '{print $1}'
}

verify_password() {
    local password="$1"
    local stored_hash="$2"
    local input_hash=$(hash_password "$password")
    [ "$input_hash" = "$stored_hash" ]
}

# ==================== VALIDATION ====================

validate_password() {
    local password="$1"

    if [ ${#password} -lt $MIN_PASSWORD_LENGTH ]; then
        echo "Password must be at least $MIN_PASSWORD_LENGTH characters"
        return 1
    fi
    if ! echo "$password" | grep -q '[A-Z]'; then
        echo "Password must contain at least one uppercase letter"
        return 1
    fi
    if ! echo "$password" | grep -q '[0-9]'; then
        echo "Password must contain at least one digit"
        return 1
    fi
    return 0
}

validate_username() {
    local username="$1"

    if [ ${#username} -lt $MIN_USERNAME_LENGTH ]; then
        echo "Username must be at least $MIN_USERNAME_LENGTH characters"
        return 1
    fi
    if ! echo "$username" | grep -qE '^[a-zA-Z0-9]+$'; then
        echo "Username must be alphanumeric"
        return 1
    fi
    return 0
}

# Strict date validation: checks format AND calendar validity
validate_date() {
    local date_str="$1"

    # Step 1: Check basic YYYY-MM-DD format
    if ! [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        return 1
    fi

    # Step 2: Check calendar validity (e.g. rejects Feb 30, month 13, etc.)
    if date -d "$date_str" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# ==================== UI & DISPLAY ====================

show_header() {
    clear
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}       $APP_NAME v$APP_VERSION${NC}"
    echo -e "${BLUE}================================================${NC}"
}

pause_prompt() {
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
}

show_menu() {
    local title="$1"
    shift
    echo -e "${YELLOW}$title${NC}"
    local i=1
    for option in "$@"; do
        echo "$i) $option"
        ((i++))
    done
    echo ""
}

get_menu_choice() {
    local max="$1"
    local choice
    while true; do
        read -p "Enter choice [1-$max]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$max" ]; then
            echo "$choice"
            return 0
        fi
        echo "Invalid choice. Please try again." >&2
    done
}

# ==================== SYSTEM & LOGGING ====================

get_date() {
    date +"$DATE_FORMAT"
}

get_time() {
    date +"$TIME_FORMAT"
}

log_action() {
    local action="$1"
    local details="$2"
    local status="${3:-SUCCESS}"
    local timestamp="$(get_date) $(get_time)"
    local user="${CURRENT_USER:-SYSTEM}"

    if [ -f "$AUDIT_TRAIL_FILE" ]; then
        echo "$timestamp,$user,$action,$details,$status" >> "$AUDIT_TRAIL_FILE"
    fi

    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [$user] [$action] $details ($status)" >> "$LOG_FILE"
    fi
}

# ==================== DATA ACCESS ====================

username_exists() {
    local username="$1"
    [ -f "$USERS_FILE" ] && grep -q "^$username," "$USERS_FILE"
}

product_id_exists() {
    local pid="$1"
    [ -f "$PRODUCTS_FILE" ] && tail -n +2 "$PRODUCTS_FILE" | grep -q "^$pid,"
}

init_csv_file() {
    local file="$1"
    local header="$2"
    if [ ! -f "$file" ]; then
        echo "$header" > "$file"
    fi
}

append_csv() {
    local file="$1"
    local data="$2"
    echo "$data" >> "$file"
}

update_csv_row() {
    local file="$1"
    local id="$2"
    local new_row="$3"
    local temp_file="${file}.tmp"

    awk -F',' -v id="$id" -v new_row="$new_row" '{
        if ($1 == id) print new_row
        else print $0
    }' "$file" > "$temp_file" && mv "$temp_file" "$file"
}

# ==================== ORDER ID GENERATION ====================

# FIX: This function was called in orders.sh but never defined anywhere — caused a crash.
# Generates the next sequential order ID by reading the highest existing one.
get_next_order_id() {
    if [ ! -f "$ORDERS_FILE" ]; then
        echo "ORD001"
        return
    fi

    # Extract all numeric parts of existing order IDs, find the max
    local max_id=$(tail -n +2 "$ORDERS_FILE" \
        | awk -F',' '{print $1}' \
        | grep -oE '[0-9]+' \
        | sort -n \
        | tail -1)

    if [ -z "$max_id" ]; then
        echo "ORD001"
    else
        # Pad to 3 digits, e.g. ORD007 -> ORD008
        local next_id=$((max_id + 1))
        printf "ORD%03d\n" "$next_id"
    fi
}

# ==================== PRODUCT DISPLAY HELPER ====================

# FIX: The inline "showproducts" table was copy-pasted 3 times across inventory.sh.
#      Extracted into a single reusable function.
show_product_list() {
    printf "%-6s | %-20s | %-8s | %-6s\n" "ID" "Name" "Price" "Qty"
    echo "------+----------------------+----------+-------"
    tail -n +2 "$PRODUCTS_FILE" 2>/dev/null | while IFS=',' read -r pid pname pprice pqty rest; do
        printf "%-6s | %-20s | %-8s | %-6s\n" "$pid" "$pname" "$pprice" "$pqty"
    done
    echo ""
}

# ==================== ALERTS ====================

get_low_stock_alerts() {
    if [ ! -f "$PRODUCTS_FILE" ]; then return; fi

    tail -n +2 "$PRODUCTS_FILE" | while IFS=',' read -r id name price qty expiry created_by; do
        if [ -z "$id" ]; then continue; fi
        qty=$(echo "$qty" | tr -d '\r')
        if [[ ! "$qty" =~ ^[0-9]+$ ]]; then continue; fi

        if [ "$qty" -eq 0 ]; then
            echo "❌ OUT OF STOCK: $name (ID: $id)"
        elif [ "$qty" -le "$LOW_STOCK_THRESHOLD" ]; then
            echo "⚠️  LOW STOCK: $name (ID: $id) - Only $qty left!"
        fi
    done
}

get_expiry_alerts() {
    if [ ! -f "$PRODUCTS_FILE" ]; then return; fi

    local current_date_sec=$(date +%s)
    local alert_date_sec=$((current_date_sec + (EXPIRY_ALERT_DAYS * 86400)))

    tail -n +2 "$PRODUCTS_FILE" | while IFS=',' read -r id name price qty expiry created_by; do
        if [ -z "$id" ]; then continue; fi

        expiry=$(echo "$expiry" | tr -d '\r')
        if ! validate_date "$expiry"; then continue; fi

        local expiry_sec=$(date -d "$expiry" +%s 2>/dev/null)
        if [ -z "$expiry_sec" ]; then continue; fi

        if [ "$expiry_sec" -lt "$current_date_sec" ]; then
            echo "💀 EXPIRED: $name (ID: $id) expired on $expiry!"
        elif [ "$expiry_sec" -le "$alert_date_sec" ]; then
            echo "⏳ EXPIRING SOON: $name (ID: $id) expires on $expiry!"
        fi
    done
}

show_alerts() {
    echo -e "${RED}=== SYSTEM ALERTS ===${NC}"

    # FIX: Collect output from subshells before checking emptiness.
    #      The old ((low++)) / ((healthy++)) counters were inside pipes (subshells)
    #      so they never affected the parent. Now we just check if output is non-empty.
    local low_stock
    low_stock=$(get_low_stock_alerts)

    local expiry_alerts
    expiry_alerts=$(get_expiry_alerts)

    if [ -n "$low_stock" ]; then
        echo "$low_stock"
    fi

    if [ -n "$expiry_alerts" ]; then
        echo "$expiry_alerts"
    fi

    if [ -z "$low_stock" ] && [ -z "$expiry_alerts" ]; then
        echo "(none) - All stock levels healthy!"
    fi

    echo -e "${RED}=====================${NC}"
    echo ""
}

# ==================== MATH ====================

# FIX: Bash $((...)) only handles integers. Prices like 19.99 caused crashes.
#      This function multiplies two decimal numbers using awk and returns an integer (floor).
multiply_price_qty() {
    local price="$1"
    local qty="$2"
    awk -v p="$price" -v q="$qty" 'BEGIN { printf "%d\n", int(p * q) }'
}

# ==================== UTILITY ====================

random_int() {
    local max="$1"
    echo $((RANDOM % max + 1))
}

# FIX: Previously only used DELIVERY_SUCCESS_RATE and DELIVERY_CANCEL_RATE,
#      ignoring DELIVERY_SENTBACK_RATE entirely. Now all three config values are used.
get_random_outcome() {
    local rand=$((RANDOM % 100 + 1))

    if [ "$rand" -le "$DELIVERY_SUCCESS_RATE" ]; then
        echo "DELIVERED"
    elif [ "$rand" -le "$((DELIVERY_SUCCESS_RATE + DELIVERY_CANCEL_RATE))" ]; then
        echo "CANCELLED"
    else
        # This range is implicitly DELIVERY_SENTBACK_RATE wide (remaining %)
        echo "SENT_BACK"
    fi
}

calculate_order_total() {
    local items_str="$1"
    local total=0

    while IFS=':' read -r product_id qty; do
        if [ -z "$product_id" ]; then continue; fi
        local price
        price=$(grep "^$product_id," "$PRODUCTS_FILE" | awk -F',' '{print $3}')
        local line_total
        line_total=$(multiply_price_qty "$price" "$qty")
        total=$((total + line_total))
    done <<< "$(echo "$items_str" | tr ',' '\n')"

    echo "$total"
}
