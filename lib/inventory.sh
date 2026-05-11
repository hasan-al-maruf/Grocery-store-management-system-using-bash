#!/bin/bash

# GSMS Inventory Module
# Handles inventory management: viewing, adding, editing, expiring products

source ./config/config.sh
source ./lib/utils.sh

# ==================== INVENTORY MENU ====================

view_inventory() {
    while true; do
        show_header
        echo "INVENTORY MENU"
        show_alerts

        show_menu "SELECT AN OPTION:" \
            "View Stock" \
            "Check Low Stock Details" \
            "Check Expiry Alerts" \
            "Add Product (Manual Entry)" \
            "Load Products from CSV" \
            "Edit Product" \
            "Mark as Expired" \
            "Back"

        local choice
        choice=$(get_menu_choice 8)

        case $choice in
            1) view_all_products ;;
            2) view_low_stock_details ;;
            3) view_expiry_alerts ;;
            4) add_products_bulk ;;
            5) load_products_from_csv ;;
            6) edit_product ;;
            7) mark_product_expired ;;
            8) return ;;
        esac
    done
}

# ==================== VIEW ====================

view_all_products() {
    show_header
    echo "===== CURRENT STOCK ====="
    echo ""

    if [ ! -f "$PRODUCTS_FILE" ]; then
        echo "No products in inventory."
        pause_prompt
        return
    fi

    printf "%-6s | %-20s | %-8s | %-6s | %-12s\n" "ID" "Name" "Price" "Qty" "Expiry"
    echo "------+----------------------+----------+--------+-------------"

    tail -n +2 "$PRODUCTS_FILE" | while IFS=',' read -r id name price qty expiry created_by; do
        if [ -n "$id" ]; then
            printf "%-6s | %-20s | %-8s | %-6s | %-12s\n" "$id" "$name" "$price" "$qty" "$expiry"
        fi
    done

    echo ""
    echo "Total products: $(tail -n +2 "$PRODUCTS_FILE" 2>/dev/null | grep -c .)"
    echo ""
    pause_prompt
}

view_low_stock_details() {
    show_header
    echo "===== LOW STOCK DETAILS ====="
    echo ""

    local alerts
    alerts=$(get_low_stock_alerts)
    if [ -z "$alerts" ]; then
        echo "No low stock items. All products are well stocked."
    else
        echo "$alerts"
    fi
    echo ""
    pause_prompt
}

view_expiry_alerts() {
    show_header
    echo "===== EXPIRY ALERTS ====="
    echo ""

    local alerts
    alerts=$(get_expiry_alerts)
    if [ -z "$alerts" ]; then
        echo "No expiring items within the next $EXPIRY_ALERT_DAYS days."
    else
        echo "$alerts"
    fi
    echo ""
    pause_prompt
}

# ==================== ADD / LOAD ====================

add_products_bulk() {
    show_header
    echo "===== ADD NEW PRODUCT ====="
    echo ""
    echo "Tip: type 'showproducts' at the ID prompt to list existing products."
    echo ""

    while true; do
        read -p "Enter Product ID: " product_id

        # FIX: Replaced inline copy-pasted table with shared show_product_list()
        if [ "$product_id" = "showproducts" ]; then
            echo ""
            show_product_list
            continue
        elif [ -z "$product_id" ]; then
            echo "ID cannot be empty."
        elif product_id_exists "$product_id"; then
            echo "Product ID already exists. Use Edit Product to update it."
        else
            break
        fi
    done

    read -p "Enter Product Name: " name

    while true; do
        read -p "Enter Price (e.g. 49.99): " price
        if [[ "$price" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            break
        else
            echo "Invalid price. Enter a positive number."
        fi
    done

    while true; do
        read -p "Enter Quantity: " qty
        if [[ "$qty" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Invalid quantity. Enter a whole number."
        fi
    done

    while true; do
        read -p "Enter Expiry Date (YYYY-MM-DD): " expiry
        if validate_date "$expiry"; then
            break
        else
            echo "❌ Invalid date. Enter a real date in YYYY-MM-DD format (e.g. $(date +%Y-%m-%d))."
        fi
    done

    local new_record="$product_id,$name,$price,$qty,$expiry,$CURRENT_USER"
    append_csv "$PRODUCTS_FILE" "$new_record"

    log_action "ADD_PRODUCT" "Added product $product_id ($name)"
    echo ""
    echo "✓ Product '$name' added successfully."
    pause_prompt
}

load_products_from_csv() {
    show_header
    echo "===== LOAD PRODUCTS FROM CSV ====="
    echo ""

    read -p "Enter path to CSV file (e.g. ./import.csv): " import_file

    if [ ! -f "$import_file" ]; then
        echo "File not found: $import_file"
        pause_prompt
        return
    fi

    local count=0
    local skipped=0

    while IFS=',' read -r id name price qty expiry rest; do
        id=$(echo "$id" | tr -d '\r')
        expiry=$(echo "$expiry" | tr -d '\r')

        # Skip blank lines and header row
        if [ -z "$id" ] || [ "$id" = "id" ] || [ "$id" = "ID" ]; then
            continue
        fi

        if ! validate_date "$expiry"; then
            echo "⚠️  Skipping ID $id: invalid date format ($expiry)"
            ((skipped++))
            continue
        fi

        if product_id_exists "$id"; then
            echo "⚠️  Skipping ID $id: already exists in system."
            ((skipped++))
        else
            append_csv "$PRODUCTS_FILE" "$id,$name,$price,$qty,$expiry,$CURRENT_USER"
            echo "✓ Imported: $id ($name)"
            ((count++))
        fi
    done < "$import_file"

    echo ""
    echo "✓ Import complete. Added: $count | Skipped: $skipped"
    log_action "IMPORT_PRODUCTS" "Imported $count products from $import_file"
    pause_prompt
}

# ==================== EDIT ====================

edit_product() {
    show_header
    echo "===== EDIT PRODUCT ====="
    echo ""
    echo "Tip: type 'showproducts' to list all products."
    echo ""

    while true; do
        read -p "Enter Product ID to edit: " product_id

        # FIX: Uses shared show_product_list() instead of copy-pasted block
        if [ "$product_id" = "showproducts" ]; then
            echo ""
            show_product_list
            continue
        elif ! product_id_exists "$product_id"; then
            echo "Product not found. Try again."
        else
            break
        fi
    done

    local product_line
    product_line=$(grep "^$product_id," "$PRODUCTS_FILE")
    IFS=',' read -r id name price qty expiry created_by <<< "$product_line"

    echo ""
    echo "Current Details:"
    printf "  Name: %-20s | Price: %-8s | Qty: %-6s | Expiry: %s\n" "$name" "$price" "$qty" "$expiry"
    echo ""

    read -p "New Name (leave blank to keep '$name'): " new_name
    new_name=${new_name:-$name}

    while true; do
        read -p "New Price (leave blank to keep '$price'): " new_price
        if [ -z "$new_price" ]; then
            new_price=$price
            break
        elif [[ "$new_price" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            break
        else
            echo "Invalid price."
        fi
    done

    while true; do
        read -p "New Qty (leave blank to keep '$qty'): " new_qty
        if [ -z "$new_qty" ]; then
            new_qty=$qty
            break
        elif [[ "$new_qty" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Invalid quantity."
        fi
    done

    while true; do
        read -p "New Expiry YYYY-MM-DD (leave blank to keep '$expiry'): " new_expiry
        if [ -z "$new_expiry" ]; then
            new_expiry=$expiry
            break
        elif validate_date "$new_expiry"; then
            break
        else
            echo "❌ Invalid date. Use YYYY-MM-DD format."
        fi
    done

    local updated_record="$id,$new_name,$new_price,$new_qty,$new_expiry,$CURRENT_USER"
    update_csv_row "$PRODUCTS_FILE" "$id" "$updated_record"

    log_action "EDIT_PRODUCT" "Updated product $id ($name)"
    echo ""
    echo "✓ Product updated successfully."
    pause_prompt
}

# ==================== MARK EXPIRED ====================

mark_product_expired() {
    show_header
    echo "===== MARK PRODUCT AS EXPIRED ====="
    echo ""
    echo "Tip: type 'showproducts' to list all products."
    echo ""

    while true; do
        read -p "Enter Product ID: " product_id

        # FIX: Uses shared show_product_list() instead of copy-pasted block
        if [ "$product_id" = "showproducts" ]; then
            echo ""
            show_product_list
            continue
        elif ! product_id_exists "$product_id"; then
            echo "Product not found. Try again."
        else
            break
        fi
    done

    local product_line
    product_line=$(grep "^$product_id," "$PRODUCTS_FILE")
    IFS=',' read -r id name price qty expiry created_by <<< "$product_line"

    echo ""
    echo "Product: $name"
    echo "Current Qty: $qty"
    echo "Expiry Date: $expiry"
    echo ""

    read -p "Mark as expired and remove from inventory? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Cancelled."
        pause_prompt
        return
    fi

    # FIX: Use multiply_price_qty to handle decimal prices safely
    local waste_value
    waste_value=$(multiply_price_qty "$price" "$qty")

    local updated_record="$id,$name,$price,0,$expiry,$CURRENT_USER"
    update_csv_row "$PRODUCTS_FILE" "$id" "$updated_record"

    init_csv_file "$LEDGER_FILE" "date,dr_account,cr_account,amount,description,created_by"
    local ledger_entry
    ledger_entry="$(get_date),Loss/Waste,Inventory,$waste_value,Product $id ($name) marked expired,$CURRENT_USER"
    append_csv "$LEDGER_FILE" "$ledger_entry"

    log_action "MARK_EXPIRED" "Product $id ($name) marked expired. Waste: $waste_value BDT"
    echo ""
    echo "✓ Product marked expired. Qty set to 0. Waste of $waste_value BDT posted to ledger."
    pause_prompt
}
