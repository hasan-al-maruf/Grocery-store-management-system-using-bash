#!/bin/bash

# GSMS Delivery Module
# Handles delivery processing with random outcomes: DELIVERED, CANCELLED, SENT_BACK

source ./config/config.sh
source ./lib/utils.sh

# ==================== DELIVERY MENU ====================

delivery_menu() {
    while true; do
        show_header
        echo "DELIVERY MENU"

        show_menu "SELECT AN OPTION:" \
            "View Delivery Queue" \
            "Process Delivery" \
            "View Delivery History" \
            "Back"

        local choice
        choice=$(get_menu_choice 4)

        case $choice in
            1) view_delivery_queue ;;
            2) process_delivery_order ;;
            3) view_delivery_history ;;
            4) return ;;
        esac
    done
}

# ==================== VIEW DELIVERY QUEUE ====================

view_delivery_queue() {
    show_header
    echo "===== DELIVERY QUEUE (PENDING orders) ====="
    echo ""

    if [ ! -f "$ORDERS_FILE" ]; then
        echo "No orders in system."
        pause_prompt
        return
    fi

    printf "%-10s | %-25s | %-10s | %-10s\n" "Order ID" "Customer" "Total" "Status"
    echo "----------+---------------------------+----------+----------"

    # FIX: Used process substitution instead of pipe so the found variable
    #      update actually persists in the current shell (not a subshell).
    local found=0
    while IFS=',' read -r order_id customer items total status created_by created_date; do
        if [ "$status" = "PENDING" ]; then
            printf "%-10s | %-25s | %-10s | %-10s\n" "$order_id" "$customer" "$total BDT" "$status"
            found=1
        fi
    done < <(tail -n +2 "$ORDERS_FILE")

    if [ "$found" -eq 0 ]; then
        echo "No pending orders in delivery queue."
    fi

    echo ""
    local pending_count
    pending_count=$(grep -c ",PENDING," "$ORDERS_FILE" 2>/dev/null || echo 0)
    echo "Total pending: $pending_count"
    echo ""
    pause_prompt
}

# ==================== PROCESS DELIVERY ====================

process_delivery_order() {
    show_header
    echo "===== PROCESS DELIVERY ====="
    echo ""

    if [ ! -f "$ORDERS_FILE" ]; then
        echo "No orders in system."
        pause_prompt
        return
    fi

    read -p "Enter Order ID to process: " order_id

    if ! grep -q "^$order_id," "$ORDERS_FILE"; then
        echo "Order not found: $order_id"
        pause_prompt
        return
    fi

    local order_line
    order_line=$(grep "^$order_id," "$ORDERS_FILE")
    IFS=',' read -r oid customer items total status created_by created_date <<< "$order_line"

    if [ "$status" != "PENDING" ]; then
        echo "Order is not PENDING. Current status: $status"
        pause_prompt
        return
    fi

    echo ""
    echo "===== PROCESSING: $order_id ====="
    echo "Customer: $customer"
    echo "Items:    $items"
    echo ""

    # Check inventory for all items
    echo "Checking inventory:"
    local all_in_stock=1
    local order_cogs=0

    while IFS=':' read -r product_id qty; do
        if [ -z "$product_id" ]; then continue; fi

        if ! product_id_exists "$product_id"; then
            echo "  ✗ Product $product_id not found in inventory"
            all_in_stock=0
            continue
        fi

        local product_line
        product_line=$(grep "^$product_id," "$PRODUCTS_FILE")
        IFS=',' read -r pid pname pprice pqty pexpiry pcreated <<< "$product_line"

        if [ "$pqty" -ge "$qty" ]; then
            echo "  ✓ $pname: need $qty, have $pqty"
            # FIX: Use multiply_price_qty to safely handle decimal prices
            local line_cogs
            line_cogs=$(multiply_price_qty "$pprice" "$qty")
            order_cogs=$((order_cogs + line_cogs))
        else
            echo "  ✗ $pname: need $qty, have $pqty → OUT OF STOCK"
            all_in_stock=0
        fi
    done <<< "$(echo "$items" | tr ',' '\n')"

    echo ""

    # Auto-cancel if any item is out of stock
    if [ "$all_in_stock" -eq 0 ]; then
        echo "One or more items are out of stock. Order will be auto-cancelled."
        echo ""

        local updated_order="$order_id,$customer,$items,$total,CANCELLED,$CURRENT_USER,$created_date"
        update_csv_row "$ORDERS_FILE" "$order_id" "$updated_order"

        init_csv_file "$LEDGER_FILE" "date,dr_account,cr_account,amount,description,created_by"
        local refund_entry
        refund_entry="$(get_date),Refund,Sales Revenue,$total,Order $order_id auto-cancelled (out of stock),$CURRENT_USER"
        append_csv "$LEDGER_FILE" "$refund_entry"

        echo "✗ ORDER CANCELLED (insufficient inventory)"
        echo "  Refund of $total BDT posted to ledger."
        echo ""

        log_action "PROCESS_DELIVERY" "Order $order_id auto-cancelled: out of stock"
        pause_prompt
        return
    fi

    # All in stock — generate probabilistic outcome
    local outcome
    outcome=$(get_random_outcome)

    echo "Dispatching order..."
    echo "[Simulated outcome: $outcome]"
    echo ""

    case $outcome in
        "DELIVERED")
            handle_delivery_delivered "$order_id" "$customer" "$items" "$total" "$order_cogs" "$created_by" "$created_date"
            ;;
        "CANCELLED")
            handle_delivery_cancelled "$order_id" "$customer" "$items" "$total" "$created_by" "$created_date"
            ;;
        "SENT_BACK")
            handle_delivery_sent_back "$order_id" "$customer" "$items" "$total" "$created_by" "$created_date"
            ;;
    esac

    pause_prompt
}

# ==================== OUTCOME HANDLERS ====================

handle_delivery_delivered() {
    local order_id="$1"
    local customer="$2"
    local items="$3"
    local total="$4"
    local cogs="$5"
    local created_by="$6"
    local created_date="$7"

    echo "✓ $order_id — DELIVERED"
    echo ""

    # Deduct delivered quantities from inventory
    echo "Updating inventory:"
    while IFS=':' read -r product_id qty; do
        if [ -z "$product_id" ]; then continue; fi

        local product_line
        product_line=$(grep "^$product_id," "$PRODUCTS_FILE")
        IFS=',' read -r pid pname pprice pqty pexpiry pcreated <<< "$product_line"

        local new_qty=$((pqty - qty))
        local updated_product="$pid,$pname,$pprice,$new_qty,$pexpiry,$pcreated"
        update_csv_row "$PRODUCTS_FILE" "$pid" "$updated_product"

        echo "  $pname: $pqty → $new_qty"
    done <<< "$(echo "$items" | tr ',' '\n')"

    local updated_order="$order_id,$customer,$items,$total,DELIVERED,$CURRENT_USER,$created_date"
    update_csv_row "$ORDERS_FILE" "$order_id" "$updated_order"

    init_csv_file "$LEDGER_FILE" "date,dr_account,cr_account,amount,description,created_by"

    # Double-entry: Revenue
    local revenue_entry
    revenue_entry="$(get_date),Cash,Sales Revenue,$total,Order $order_id delivered,$CURRENT_USER"
    append_csv "$LEDGER_FILE" "$revenue_entry"

    # Double-entry: Cost of Goods Sold
    local cogs_entry
    cogs_entry="$(get_date),Cost of Goods Sold,Inventory,$cogs,Order $order_id cost of goods,$CURRENT_USER"
    append_csv "$LEDGER_FILE" "$cogs_entry"

    echo ""
    echo "Ledger entries posted:"
    echo "  Dr. Cash:             $total BDT"
    echo "  Cr. Sales Revenue:    $total BDT"
    echo "  Dr. COGS:             $cogs BDT"
    echo "  Cr. Inventory:        $cogs BDT"
    echo ""

    log_action "PROCESS_DELIVERY" "Order $order_id DELIVERED. Revenue=$total BDT, COGS=$cogs BDT"
}

handle_delivery_cancelled() {
    local order_id="$1"
    local customer="$2"
    local items="$3"
    local total="$4"
    local created_by="$5"
    local created_date="$6"

    echo "✗ $order_id — CANCELLED during delivery"
    echo ""

    local updated_order="$order_id,$customer,$items,$total,CANCELLED,$CURRENT_USER,$created_date"
    update_csv_row "$ORDERS_FILE" "$order_id" "$updated_order"

    init_csv_file "$LEDGER_FILE" "date,dr_account,cr_account,amount,description,created_by"
    local refund_entry
    refund_entry="$(get_date),Refund,Sales Revenue,$total,Order $order_id cancelled during delivery,$CURRENT_USER"
    append_csv "$LEDGER_FILE" "$refund_entry"

    echo "Ledger entries posted:"
    echo "  Dr. Refund:           $total BDT"
    echo "  Cr. Sales Revenue:    $total BDT"
    echo ""

    log_action "PROCESS_DELIVERY" "Order $order_id CANCELLED during delivery. Refund=$total BDT"
}

handle_delivery_sent_back() {
    local order_id="$1"
    local customer="$2"
    local items="$3"
    local total="$4"
    local created_by="$5"
    local created_date="$6"

    echo "⚠️  $order_id — SENT BACK (partial return)"
    echo ""

    # 50% partial delivery assumption
    local delivered_amount=$((total / 2))
    local return_amount=$((total - delivered_amount))

    # Deduct only the delivered half from inventory
    echo "Updating inventory (50% delivered, 50% returned):"
    while IFS=':' read -r product_id qty; do
        if [ -z "$product_id" ]; then continue; fi

        local product_line
        product_line=$(grep "^$product_id," "$PRODUCTS_FILE")
        IFS=',' read -r pid pname pprice pqty pexpiry pcreated <<< "$product_line"

        local delivered_qty=$((qty / 2))
        local returned_qty=$((qty - delivered_qty))
        local new_qty=$((pqty - delivered_qty))

        local updated_product="$pid,$pname,$pprice,$new_qty,$pexpiry,$pcreated"
        update_csv_row "$PRODUCTS_FILE" "$pid" "$updated_product"

        echo "  $pname: delivered $delivered_qty, returned $returned_qty"
    done <<< "$(echo "$items" | tr ',' '\n')"

    local updated_order="$order_id,$customer,$items,$total,SENT_BACK,$CURRENT_USER,$created_date"
    update_csv_row "$ORDERS_FILE" "$order_id" "$updated_order"

    init_csv_file "$LEDGER_FILE" "date,dr_account,cr_account,amount,description,created_by"

    local revenue_entry
    revenue_entry="$(get_date),Cash,Sales Revenue,$delivered_amount,Order $order_id partial delivery,$CURRENT_USER"
    append_csv "$LEDGER_FILE" "$revenue_entry"

    local return_entry
    return_entry="$(get_date),Return Adjustment,Sales Revenue,$return_amount,Order $order_id partial return,$CURRENT_USER"
    append_csv "$LEDGER_FILE" "$return_entry"

    echo ""
    echo "Ledger entries posted:"
    echo "  Dr. Cash:                $delivered_amount BDT  (delivered portion)"
    echo "  Cr. Sales Revenue:       $delivered_amount BDT"
    echo "  Dr. Return Adjustment:   $return_amount BDT  (returned portion)"
    echo "  Cr. Sales Revenue:       $return_amount BDT"
    echo ""

    log_action "PROCESS_DELIVERY" "Order $order_id SENT_BACK. Delivered=$delivered_amount BDT, Returned=$return_amount BDT"
}

# ==================== VIEW DELIVERY HISTORY ====================

view_delivery_history() {
    show_header
    echo "===== DELIVERY HISTORY ====="
    echo ""

    if [ ! -f "$ORDERS_FILE" ]; then
        echo "No orders in system."
        pause_prompt
        return
    fi

    printf "%-10s | %-25s | %-10s | %-12s\n" "Order ID" "Customer" "Total" "Status"
    echo "----------+---------------------------+----------+------------"

    while IFS=',' read -r order_id customer items total status created_by created_date; do
        if [ "$status" != "PENDING" ]; then
            printf "%-10s | %-25s | %-10s | %-12s\n" "$order_id" "$customer" "$total BDT" "$status"
        fi
    done < <(tail -n +2 "$ORDERS_FILE")

    echo ""

    local delivered cancelled sent_back total_processed
    delivered=$(grep -c ",DELIVERED," "$ORDERS_FILE" 2>/dev/null || echo 0)
    cancelled=$(grep -c ",CANCELLED," "$ORDERS_FILE" 2>/dev/null || echo 0)
    sent_back=$(grep -c ",SENT_BACK," "$ORDERS_FILE" 2>/dev/null || echo 0)
    total_processed=$((delivered + cancelled + sent_back))

    if [ "$total_processed" -gt 0 ]; then
        echo "===== SUMMARY ====="
        echo "  Total Processed: $total_processed"
        echo "  Delivered:       $delivered"
        echo "  Cancelled:       $cancelled"
        echo "  Sent Back:       $sent_back"
        echo "  Success Rate:    $(( (delivered * 100) / total_processed ))%"
    else
        echo "No processed orders yet."
    fi

    echo ""
    pause_prompt
}
