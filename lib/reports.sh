#!/bin/bash

# GSMS Reports Module
# Generates P&L, inventory health, delivery performance, and audit reports

source ./config/config.sh
source ./lib/utils.sh

# ==================== REPORTS MENU ====================

reports_menu() {
    while true; do
        show_header
        echo "REPORTS MENU"

        show_menu "SELECT AN OPTION:" \
            "Profit & Loss Statement" \
            "Inventory Health" \
            "Delivery Performance" \
            "Audit Trail Report" \
            "Back"

        local choice
        choice=$(get_menu_choice 5)

        case $choice in
            1) profit_loss_report ;;
            2) inventory_health_report ;;
            3) delivery_performance_report ;;
            4) audit_trail_report ;;
            5) return ;;
        esac
    done
}

# ==================== PROFIT & LOSS REPORT ====================

profit_loss_report() {
    show_header
    echo "===== PROFIT & LOSS STATEMENT ====="
    echo ""

    if [ ! -f "$LEDGER_FILE" ]; then
        echo "No ledger entries found."
        pause_prompt
        return
    fi

    local start_date=""
    while true; do
        read -p "Enter start date (YYYY-MM-DD) or press Enter for all: " input_date
        input_date=$(echo "$input_date" | xargs)

        if [ -z "$input_date" ]; then
            break
        elif validate_date "$input_date"; then
            start_date="$input_date"
            break
        else
            echo "❌ Invalid date. Use YYYY-MM-DD format."
        fi
    done

    local total_sales total_refunds total_returns total_cogs total_waste total_delivery

    total_sales=$(tail -n +2 "$LEDGER_FILE" | awk -F',' -v d="$start_date" \
        '$3=="Sales Revenue" && (d=="" || $1>=d) {sum+=$4} END {printf "%d", sum}')

    total_refunds=$(tail -n +2 "$LEDGER_FILE" | awk -F',' -v d="$start_date" \
        '$2=="Refund" && (d=="" || $1>=d) {sum+=$4} END {printf "%d", sum}')

    total_returns=$(tail -n +2 "$LEDGER_FILE" | awk -F',' -v d="$start_date" \
        '$2=="Return Adjustment" && (d=="" || $1>=d) {sum+=$4} END {printf "%d", sum}')

    total_cogs=$(tail -n +2 "$LEDGER_FILE" | awk -F',' -v d="$start_date" \
        '$2=="Cost of Goods Sold" && (d=="" || $1>=d) {sum+=$4} END {printf "%d", sum}')

    total_waste=$(tail -n +2 "$LEDGER_FILE" | awk -F',' -v d="$start_date" \
        '$2=="Loss/Waste" && (d=="" || $1>=d) {sum+=$4} END {printf "%d", sum}')

    total_delivery=$(tail -n +2 "$LEDGER_FILE" | awk -F',' -v d="$start_date" \
        '$2=="Delivery Expense" && (d=="" || $1>=d) {sum+=$4} END {printf "%d", sum}')

    total_sales=${total_sales:-0}
    total_refunds=${total_refunds:-0}
    total_returns=${total_returns:-0}
    total_cogs=${total_cogs:-0}
    total_waste=${total_waste:-0}
    total_delivery=${total_delivery:-0}

    local net_revenue total_expenses net_profit
    net_revenue=$((total_sales - total_refunds - total_returns))
    total_expenses=$((total_cogs + total_waste + total_delivery))
    net_profit=$((net_revenue - total_expenses))

    if [ -n "$start_date" ]; then
        echo "Period: From $start_date to $(get_date)"
    else
        echo "Period: All time"
    fi
    echo ""
    echo "REVENUE:"
    printf "  %-30s %10s BDT\n" "Sales Revenue:"         "$total_sales"
    printf "  %-30s %10s BDT\n" "Less: Refunds:"        "-$total_refunds"
    printf "  %-30s %10s BDT\n" "Less: Returns:"        "-$total_returns"
    echo "  ─────────────────────────────────────────"
    printf "  %-30s %10s BDT\n" "Net Revenue:"           "$net_revenue"
    echo ""
    echo "EXPENSES:"
    printf "  %-30s %10s BDT\n" "Cost of Goods Sold:"   "$total_cogs"
    printf "  %-30s %10s BDT\n" "Loss/Waste:"           "$total_waste"
    printf "  %-30s %10s BDT\n" "Delivery Expense:"     "$total_delivery"
    echo "  ─────────────────────────────────────────"
    printf "  %-30s %10s BDT\n" "Total Expenses:"       "$total_expenses"
    echo ""
    echo "  ========================================="
    printf "  %-30s %10s BDT\n" "NET PROFIT / (LOSS):" "$net_profit"
    echo "  ========================================="
    echo ""

    if [ "$net_profit" -gt 0 ]; then
        echo -e "${GREEN}✓ Profitable period${NC}"
    elif [ "$net_profit" -lt 0 ]; then
        echo -e "${RED}✗ Loss-making period${NC}"
    else
        echo "⚠️  Break-even period"
    fi

    echo ""
    pause_prompt
}

# ==================== INVENTORY HEALTH REPORT ====================

inventory_health_report() {
    show_header
    echo "===== INVENTORY HEALTH REPORT ====="
    echo ""

    if [ ! -f "$PRODUCTS_FILE" ]; then
        echo "No products in inventory."
        pause_prompt
        return
    fi

    echo "Stock Status (threshold: $LOW_STOCK_THRESHOLD units):"
    echo ""
    printf "%-22s | %-6s | %-8s\n" "Product" "Qty" "Status"
    echo "----------------------+-------+--------"

    # FIX: Use process substitution so the healthy/low counters persist in parent shell
    local healthy=0
    local low=0
    local out=0

    while IFS=',' read -r id name price qty expiry created_by; do
        qty=$(echo "$qty" | tr -d '\r')
        if [[ ! "$qty" =~ ^[0-9]+$ ]]; then continue; fi

        if [ "$qty" -eq 0 ]; then
            printf "%-22s | %-6s | OUT OF STOCK\n" "$name" "$qty"
            ((out++))
        elif [ "$qty" -lt "$LOW_STOCK_THRESHOLD" ]; then
            printf "%-22s | %-6s | LOW\n" "$name" "$qty"
            ((low++))
        else
            printf "%-22s | %-6s | OK\n" "$name" "$qty"
            ((healthy++))
        fi
    done < <(tail -n +2 "$PRODUCTS_FILE")

    echo ""
    echo "Summary: OK=$healthy | Low=$low | Out of stock=$out"
    echo ""

    echo "Expiry Status:"
    echo ""

    local today_sec expired_count expiring_count
    today_sec=$(date +%s)
    expired_count=0
    expiring_count=0

    while IFS=',' read -r id name price qty expiry created_by; do
        expiry=$(echo "$expiry" | tr -d '\r')
        if ! validate_date "$expiry"; then continue; fi

        local expiry_sec
        expiry_sec=$(date -d "$expiry" +%s 2>/dev/null)
        if [ -z "$expiry_sec" ]; then continue; fi

        if [ "$expiry_sec" -lt "$today_sec" ]; then
            echo "  💀 EXPIRED:        $name (expired $expiry)"
            ((expired_count++))
        else
            local days_left=$(( (expiry_sec - today_sec) / 86400 ))
            if [ "$days_left" -le "$EXPIRY_ALERT_DAYS" ]; then
                echo "  ⏳ EXPIRING SOON:  $name (expires in $days_left day(s) on $expiry)"
                ((expiring_count++))
            fi
        fi
    done < <(tail -n +2 "$PRODUCTS_FILE")

    if [ "$expired_count" -eq 0 ] && [ "$expiring_count" -eq 0 ]; then
        echo "  All products have healthy expiry dates."
    fi

    echo ""

    # FIX: Was using grep -c "$LOW_STOCK_THRESHOLD" which matched the threshold
    #      number as a string anywhere in the file — completely wrong.
    #      Now uses the correct low+out count from the loop above.
    local reorder_count=$((low + out))
    echo "Products needing reorder: $reorder_count"
    echo ""
    pause_prompt
}

# ==================== DELIVERY PERFORMANCE REPORT ====================

delivery_performance_report() {
    show_header
    echo "===== DELIVERY PERFORMANCE REPORT ====="
    echo ""

    if [ ! -f "$ORDERS_FILE" ]; then
        echo "No orders in system."
        pause_prompt
        return
    fi

    local delivered cancelled sent_back pending
    delivered=$(grep -c ",DELIVERED," "$ORDERS_FILE" 2>/dev/null || echo 0)
    cancelled=$(grep -c ",CANCELLED," "$ORDERS_FILE" 2>/dev/null || echo 0)
    sent_back=$(grep -c ",SENT_BACK," "$ORDERS_FILE" 2>/dev/null || echo 0)
    pending=$(grep -c ",PENDING," "$ORDERS_FILE" 2>/dev/null || echo 0)

    local total_processed total_all
    total_processed=$((delivered + cancelled + sent_back))
    total_all=$((total_processed + pending))

    echo "Order Status Distribution:"
    echo ""
    printf "%-15s | %-6s | %-8s\n" "Status" "Count" "Percent"
    echo "---------------+-------+--------"

    if [ "$total_all" -gt 0 ]; then
        printf "%-15s | %-6s | %s%%\n" "Delivered"  "$delivered"  "$(( (delivered  * 100) / total_all ))"
        printf "%-15s | %-6s | %s%%\n" "Cancelled"  "$cancelled"  "$(( (cancelled  * 100) / total_all ))"
        printf "%-15s | %-6s | %s%%\n" "Sent Back"  "$sent_back"  "$(( (sent_back  * 100) / total_all ))"
        printf "%-15s | %-6s | %s%%\n" "Pending"    "$pending"    "$(( (pending    * 100) / total_all ))"
    fi

    echo ""

    if [ "$total_processed" -gt 0 ]; then
        echo "Success Rate (Delivered / Processed): $(( (delivered * 100) / total_processed ))%"
    fi

    echo "Total Processed: $total_processed"
    echo "Total Pending:   $pending"
    echo ""

    # Simulated delivery probability display
    echo "Configured Delivery Probabilities:"
    echo "  Delivered:  $DELIVERY_SUCCESS_RATE%"
    echo "  Cancelled:  $DELIVERY_CANCEL_RATE%"
    echo "  Sent Back:  $DELIVERY_SENTBACK_RATE%"
    echo ""

    pause_prompt
}

# ==================== AUDIT TRAIL REPORT ====================

audit_trail_report() {
    show_header
    echo "===== AUDIT TRAIL REPORT ====="
    echo ""

    if [ ! -f "$AUDIT_TRAIL_FILE" ]; then
        echo "No audit entries found."
        pause_prompt
        return
    fi

    show_menu "FILTER BY:" \
        "All Actions" \
        "By Username" \
        "By Action Type" \
        "Back"

    local choice
    choice=$(get_menu_choice 4)

    case $choice in
        1) display_audit_all ;;
        2) display_audit_by_user ;;
        3) display_audit_by_action ;;
        4) return ;;
    esac
}

display_audit_all() {
    show_header
    echo "===== COMPLETE AUDIT TRAIL ====="
    echo ""

    printf "%-22s | %-14s | %-20s | %-30s | %-10s\n" \
        "Timestamp" "Username" "Action" "Details" "Status"
    echo "----------------------+----------------+--------------------+------------------------------+----------"

    while IFS=',' read -r timestamp username action details status; do
        printf "%-22s | %-14s | %-20s | %-30s | %-10s\n" \
            "$timestamp" "$username" "$action" "$details" "$status"
    done < <(tail -n +2 "$AUDIT_TRAIL_FILE")

    echo ""
    echo "Total entries: $(tail -n +2 "$AUDIT_TRAIL_FILE" 2>/dev/null | grep -c .)"
    echo ""
    pause_prompt
}

display_audit_by_user() {
    show_header
    echo "===== AUDIT TRAIL BY USER ====="
    echo ""

    read -p "Enter username to filter: " filter_user

    echo ""
    printf "%-22s | %-20s | %-30s\n" "Timestamp" "Action" "Details"
    echo "----------------------+--------------------+------------------------------"

    tail -n +2 "$AUDIT_TRAIL_FILE" | awk -F',' -v user="$filter_user" \
        '$2==user {printf "%-22s | %-20s | %-30s\n", $1, $3, $4}'

    echo ""
    pause_prompt
}

display_audit_by_action() {
    show_header
    echo "===== AUDIT TRAIL BY ACTION ====="
    echo ""

    read -p "Enter action type (e.g. LOGIN, CREATE_ORDER, ADD_PRODUCT): " filter_action

    echo ""
    printf "%-22s | %-14s | %-30s\n" "Timestamp" "Username" "Details"
    echo "----------------------+----------------+------------------------------"

    tail -n +2 "$AUDIT_TRAIL_FILE" | awk -F',' -v action="$filter_action" \
        '$3==action {printf "%-22s | %-14s | %-30s\n", $1, $2, $4}'

    echo ""
    pause_prompt
}
