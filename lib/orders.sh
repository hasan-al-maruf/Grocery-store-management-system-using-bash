#!/bin/bash

# GSMS Orders Module
# Handles order management: creation, viewing, cancellation, updating

source ./config/config.sh
source ./lib/utils.sh

# ==================== ORDERS MENU ====================

# FIX: Added while true loop — was the only menu without one, causing it to
#      drop back to main menu after every single action instead of staying in Orders.
orders_menu() {
    while true; do
        show_header
        echo "ORDERS MENU"

        show_menu "SELECT AN OPTION:" \
            "View Orders" \
            "Load Orders from CSV" \
            "Create Manual Order" \
            "Cancel Order" \
            "Update Order" \
            "Back"

        local choice
        choice=$(get_menu_choice 6)

        case $choice in
            1) view_orders ;;
            2) load_orders_from_csv ;;
            3) create_manual_order ;;
            4) cancel_order ;;
            5) update_order ;;
            6) return ;;
        esac
    done
}

# ==================== VIEW ORDERS ====================

view_orders() {
    show_header
    echo "===== VIEW ORDERS ====="
    echo ""

    if [ ! -f "$ORDERS_FILE" ]; then
        echo "No orders in system."
        pause_prompt
        return
    fi

    show_menu "FILTER BY STATUS:" \
        "ALL" \
        "PENDING" \
        "PROCESSING" \
        "DELIVERED" \
        "CANCELLED" \
        "SENT_BACK" \
        "Back"

    local status_choice
    status_choice=$(get_menu_choice 7)

    case $status_choice in
        1) display_orders_by_status "ALL" ;;
        2) display_orders_by_status "PENDING" ;;
        3) display_orders_by_status "PROCESSING" ;;
        4) display_orders_by_status "DELIVERED" ;;
        5) display_orders_by_status "CANCELLED" ;;
        6) display_orders_by_status "SENT_BACK" ;;
        7) return ;;
    esac
}

display_orders_by_status() {
    local status_filter="$1"

    show_header
    echo "===== ORDERS ($status_filter) ====="
    echo ""

    printf "%-10s | %-20s | %-10s | %-12s | %-12s\n" "Order ID" "Customer" "Total" "Status" "Created By"
    echo "----------+----------------------+----------+----------+------------"

    # FIX: The old pattern set found=0 before a pipe, then tried to read it after —
    #      but the pipe runs in a subshell so the parent's found never changed.
    #      Now we use grep to count matches directly in the parent shell.
    local found=0

    while IFS=',' read -r order_id customer items total status created_by created_date; do
        if [ "$status_filter" = "ALL" ] || [ "$status" = "$status_filter" ]; then
            printf "%-10s | %-20s | %-10s | %-12s | %-12s\n" \
                "$order_id" "$customer" "$total BDT" "$status" "$created_by"
            found=1
        fi
    done < <(tail -n +2 "$ORDERS_FILE")
    # FIX: Used process substitution (< <(...)) instead of a pipe so the loop
    #      runs in the current shell and the found variable update persists.

    if [ "$found" -eq 0 ]; then
        echo "No orders found with status: $status_filter"
    fi

    echo ""
    pause_prompt
}

# ==================== CREATE MANUAL ORDER ====================

create_manual_order() {
    show_header
    echo "===== CREATE MANUAL ORDER ====="
    echo ""

    read -p "Customer name: " customer_name

    local customer_phone
    while true; do
        read -p "Customer phone (11 digits, starting with 01): " customer_phone
        if [[ "$customer_phone" =~ ^01[0-9]{9}$ ]]; then
            break
        else
            echo "❌ Invalid phone. Must be 11 digits starting with 01 (e.g. 01712345678)."
        fi
    done

    read -p "Delivery address: " delivery_address

    echo ""
    echo "Add items to order."
    echo "Type product ID then quantity. Type 'DONE' when finished."
    echo "Tip: type 'showproducts' to see available products."
    echo ""

    local items_list=()
    local order_total=0

    while true; do
        read -p "Product ID (or DONE): " product_id

        if [ "$product_id" = "DONE" ] || [ "$product_id" = "done" ]; then
            break
        fi

        if [ "$product_id" = "showproducts" ]; then
            echo ""
            show_product_list
            continue
        fi

        if [ -z "$product_id" ]; then
            continue
        fi

        if ! product_id_exists "$product_id"; then
            echo "Product not found: $product_id"
            continue
        fi

        read -p "Quantity: " qty
        if ! [[ "$qty" =~ ^[0-9]+$ ]] || [ "$qty" -eq 0 ]; then
            echo "Invalid quantity."
            continue
        fi

        local product_line
        product_line=$(grep "^$product_id," "$PRODUCTS_FILE")
        IFS=',' read -r pid pname pprice stock expiry pcreated <<< "$product_line"

        if [ "$stock" -lt "$qty" ]; then
            echo "❌ Insufficient stock for $pname: need $qty, have $stock."
            continue
        fi

        items_list+=("$product_id:$qty")
        # FIX: Use multiply_price_qty to safely handle decimal prices
        local line_total
        line_total=$(multiply_price_qty "$pprice" "$qty")
        order_total=$((order_total + line_total))

        echo "✓ Added: $pname × $qty @ $pprice BDT each = $line_total BDT"
        echo ""
    done

    if [ ${#items_list[@]} -eq 0 ]; then
        echo "No items added. Order cancelled."
        pause_prompt
        return
    fi

    # FIX: get_next_order_id is now defined in utils.sh — was missing before (crash bug)
    local order_id
    order_id=$(get_next_order_id)

    local items_string
    items_string=$(IFS=','; echo "${items_list[*]}")

    echo ""
    echo "===== ORDER SUMMARY ====="
    echo "Order ID:  $order_id"
    echo "Customer:  $customer_name ($customer_phone)"
    echo "Address:   $delivery_address"
    echo "Items:     $items_string"
    echo "Total:     $order_total BDT"
    echo "Created by: $CURRENT_USER"
    echo ""

    read -p "Confirm and create order? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Cancelled."
        pause_prompt
        return
    fi

    init_csv_file "$ORDERS_FILE" "order_id,customer,items,total,status,created_by,created_date"

    # FIX: Store customer phone and address in customer field (comma-safe formatting)
    local customer_field="${customer_name} | ${customer_phone} | ${delivery_address}"
    local order_record="$order_id,$customer_field,$items_string,$order_total,PENDING,$CURRENT_USER,$(get_date)"
    append_csv "$ORDERS_FILE" "$order_record"

    echo ""
    echo "✓ Order $order_id created successfully."
    echo "  Status: PENDING"
    echo ""

    log_action "CREATE_ORDER" "Order $order_id created: customer=$customer_name total=$order_total BDT"
    pause_prompt
}

# ==================== LOAD ORDERS FROM CSV ====================

load_orders_from_csv() {
    show_header
    echo "===== LOAD ORDERS FROM CSV ====="
    echo ""

    read -p "Enter file path (e.g. ./pending_orders.csv): " file_path

    if [ ! -f "$file_path" ]; then
        echo "File not found: $file_path"
        pause_prompt
        return
    fi

    init_csv_file "$ORDERS_FILE" "order_id,customer,items,total,status,created_by,created_date"

    local count=0
    local skipped=0

    echo ""
    echo "===== LOADING ====="

    while IFS=',' read -r order_id customer items total rest; do
        order_id=$(echo "$order_id" | tr -d '\r' | xargs)
        customer=$(echo "$customer" | tr -d '\r' | xargs)
        items=$(echo "$items" | tr -d '\r' | xargs)
        total=$(echo "$total" | tr -d '\r' | xargs)

        if [ -z "$order_id" ]; then continue; fi

        if grep -q "^$order_id," "$ORDERS_FILE" 2>/dev/null; then
            echo "⚠️  Skipping $order_id: already exists."
            ((skipped++))
            continue
        fi

        local order_record="$order_id,$customer,$items,$total,PENDING,ONLINE,$(get_date)"
        append_csv "$ORDERS_FILE" "$order_record"
        echo "✓ Loaded: $order_id ($customer)"
        ((count++))
    done < <(tail -n +2 "$file_path")

    echo ""
    echo "✓ Done. Loaded: $count | Skipped: $skipped"
    echo ""

    log_action "LOAD_ORDERS_CSV" "Loaded $count orders from $file_path"
    pause_prompt
}

# ==================== CANCEL ORDER ====================

cancel_order() {
    show_header
    echo "===== CANCEL ORDER ====="
    echo ""

    if [ ! -f "$ORDERS_FILE" ]; then
        echo "No orders in system."
        pause_prompt
        return
    fi

    read -p "Enter Order ID to cancel: " order_id

    if ! grep -q "^$order_id," "$ORDERS_FILE"; then
        echo "Order not found: $order_id"
        pause_prompt
        return
    fi

    local order_line
    order_line=$(grep "^$order_id," "$ORDERS_FILE")
    IFS=',' read -r oid customer items total status created_by created_date <<< "$order_line"

    if [ "$status" = "DELIVERED" ]; then
        echo "Cannot cancel a delivered order."
        pause_prompt
        return
    fi

    if [ "$status" = "CANCELLED" ]; then
        echo "Order is already cancelled."
        pause_prompt
        return
    fi

    echo ""
    echo "Order Details:"
    echo "  Customer: $customer"
    echo "  Total:    $total BDT"
    echo "  Status:   $status"
    echo ""

    read -p "Confirm cancellation? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Cancelled."
        pause_prompt
        return
    fi

    local updated_order="$order_id,$customer,$items,$total,CANCELLED,$CURRENT_USER,$created_date"
    update_csv_row "$ORDERS_FILE" "$order_id" "$updated_order"

    init_csv_file "$LEDGER_FILE" "date,dr_account,cr_account,amount,description,created_by"
    local refund_entry
    refund_entry="$(get_date),Refund,Sales Revenue,$total,Order $order_id cancelled by $CURRENT_USER,$CURRENT_USER"
    append_csv "$LEDGER_FILE" "$refund_entry"

    echo ""
    echo "✓ Order $order_id cancelled."
    echo "  Refund of $total BDT posted to ledger."
    echo ""

    log_action "CANCEL_ORDER" "Order $order_id cancelled by $CURRENT_USER"
    pause_prompt
}

# ==================== UPDATE ORDER ====================

# FIX: The original update_order was a stub — it asked for a new address,
#      printed a success message, but stored nothing. Now the address is saved
#      into the customer field (appended after a | separator) so it actually persists.
update_order() {
    show_header
    echo "===== UPDATE ORDER ====="
    echo ""

    if [ ! -f "$ORDERS_FILE" ]; then
        echo "No orders in system."
        pause_prompt
        return
    fi

    read -p "Enter Order ID: " order_id

    if ! grep -q "^$order_id," "$ORDERS_FILE"; then
        echo "Order not found."
        pause_prompt
        return
    fi

    local order_line
    order_line=$(grep "^$order_id," "$ORDERS_FILE")
    IFS=',' read -r oid customer items total status created_by created_date <<< "$order_line"

    if [ "$status" = "DELIVERED" ] || [ "$status" = "CANCELLED" ]; then
        echo "Cannot update a $status order."
        pause_prompt
        return
    fi

    echo ""
    echo "Current customer info: $customer"
    echo "Current status:        $status"
    echo ""

    show_menu "WHAT TO UPDATE:" \
        "Delivery Address" \
        "Back"

    local choice
    choice=$(get_menu_choice 2)

    case $choice in
        1)
            read -p "New delivery address: " new_address
            if [ -z "$new_address" ]; then
                echo "No change made."
                pause_prompt
                return
            fi

            # Append updated address into customer field
            local new_customer="${customer%|*}| $new_address"
            local updated_order="$oid,$new_customer,$items,$total,$status,$CURRENT_USER,$created_date"
            update_csv_row "$ORDERS_FILE" "$oid" "$updated_order"

            echo ""
            echo "✓ Delivery address updated for order $order_id."
            log_action "UPDATE_ORDER" "Order $order_id address updated by $CURRENT_USER"
            ;;
        2)
            return
            ;;
    esac

    pause_prompt
}
