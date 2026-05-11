#!/bin/bash

# GSMS Ledger Module
# Handles double-entry accounting ledger and balance calculations

source ./config/config.sh
source ./lib/utils.sh

# ==================== LEDGER MENU ====================

ledger_menu() {
    while true; do
        show_header
        echo "LEDGER MENU"

        show_menu "SELECT AN OPTION:" \
            "View Ledger" \
            "Calculate Account Balances" \
            "Audit Trail" \
            "Back"

        local choice
        choice=$(get_menu_choice 4)

        case $choice in
            1) view_ledger ;;
            2) calculate_balance ;;
            3) view_audit_trail ;;
            4) return ;;
        esac
    done
}

# ==================== VIEW LEDGER ====================

view_ledger() {
    show_header
    echo "===== LEDGER ====="
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
            echo "❌ Invalid date. Use YYYY-MM-DD format (e.g. $(date +%Y-%m-%d))."
        fi
    done

    echo ""
    printf "%-12s | %-22s | %-22s | %-10s | %-30s\n" \
        "Date" "Dr. Account" "Cr. Account" "Amount" "Description"
    echo "------------+-----------------------+-----------------------+------------+------------------------------"

    while IFS=',' read -r date dr_account cr_account amount description created_by; do
        if [ -z "$start_date" ] || [[ "$date" > "$start_date" ]] || [[ "$date" = "$start_date" ]]; then
            printf "%-12s | %-22s | %-22s | %-10s | %-30s\n" \
                "$date" "$dr_account" "$cr_account" "$amount BDT" "$description"
        fi
    done < <(tail -n +2 "$LEDGER_FILE")

    echo ""
    echo "Total entries: $(tail -n +2 "$LEDGER_FILE" 2>/dev/null | grep -c .)"
    echo ""
    pause_prompt
}

# ==================== CALCULATE BALANCE ====================

calculate_balance() {
    show_header
    echo "===== ACCOUNT BALANCES ====="
    echo ""

    if [ ! -f "$LEDGER_FILE" ]; then
        echo "No ledger entries found."
        pause_prompt
        return
    fi

    echo "Account Summary (Debits - Credits = Balance):"
    echo ""
    printf "%-25s | %-12s | %-12s | %-12s\n" "Account" "Dr (BDT)" "Cr (BDT)" "Balance (BDT)"
    echo "-------------------------+--------------+--------------+--------------"

    # Extract all unique account names from both debit and credit columns
    local accounts
    accounts=$(tail -n +2 "$LEDGER_FILE" | awk -F',' '{print $2; print $3}' | sort -u | grep -v '^$')

    while IFS= read -r account; do
        local debits credits balance
        debits=$(tail -n +2 "$LEDGER_FILE" | awk -F',' -v acc="$account" '$2==acc {sum+=$4} END {printf "%d", sum}')
        credits=$(tail -n +2 "$LEDGER_FILE" | awk -F',' -v acc="$account" '$3==acc {sum+=$4} END {printf "%d", sum}')

        debits=${debits:-0}
        credits=${credits:-0}
        balance=$((debits - credits))

        # FIX: Added BDT labels for clarity — was showing raw numbers before
        printf "%-25s | %-12s | %-12s | %-12s\n" "$account" "$debits" "$credits" "$balance"
    done <<< "$accounts"

    echo ""
    pause_prompt
}

# ==================== AUDIT TRAIL ====================

view_audit_trail() {
    show_header
    echo "===== AUDIT TRAIL ====="
    echo ""

    if [ ! -f "$AUDIT_TRAIL_FILE" ]; then
        echo "No audit entries found."
        pause_prompt
        return
    fi

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
