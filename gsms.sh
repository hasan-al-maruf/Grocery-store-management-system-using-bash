#!/bin/bash

# GSMS Main Entry Point
# Grocery Store Management System v1.0

# Source all modules
source ./config/config.sh
source ./lib/utils.sh
source ./lib/auth.sh
source ./lib/inventory.sh
source ./lib/orders.sh
source ./lib/delivery.sh
source ./lib/ledger.sh
source ./lib/reports.sh

# ==================== MAIN MENU ====================

main_menu() {
    while true; do
        show_header
        echo "Logged in as: $CURRENT_USER"
        echo "Date: $(get_date) | Time: $(get_time)"
        echo ""

        show_menu "MAIN MENU:" \
            "Inventory" \
            "Orders" \
            "Delivery" \
            "Ledger" \
            "Reports" \
            "Add New Manager Account" \
            "Logout & Exit"

        local choice
        choice=$(get_menu_choice 7)

        case $choice in
            1) view_inventory ;;
            2) orders_menu ;;
            3) delivery_menu ;;
            4) ledger_menu ;;
            5) reports_menu ;;
            6) add_new_user ;;
            7)
                logout_user
                show_header
                echo "Logged out. Thank you for using $APP_NAME."
                echo ""
                exit 0
                ;;
        esac
    done
}

# ==================== STARTUP ====================

startup() {
    # Run authentication (handles first-boot registration automatically)
    run_authentication

    # Welcome screen
    show_header
    echo "Welcome, $CURRENT_USER!"
    echo "Date: $(get_date) | Time: $(get_time)"
    echo ""
    echo "Initializing system..."
    echo ""

    # Initialize CSV files with headers if they don't exist yet
    init_csv_file "$PRODUCTS_FILE"    "id,name,price,qty,expiry_date,created_by"
    init_csv_file "$ORDERS_FILE"      "order_id,customer,items,total,status,created_by,created_date"
    init_csv_file "$LEDGER_FILE"      "date,dr_account,cr_account,amount,description,created_by"
    init_csv_file "$AUDIT_TRAIL_FILE" "timestamp,username,action,details,status"

    log_action "APP_START" "Application started"

    echo "System ready."
    pause_prompt

    main_menu
}

# ==================== RUN APPLICATION ====================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    startup
fi
