#!/bin/bash

# GSMS Authentication Module
# Handles user registration (first-boot), multiple users, and login

source ./config/config.sh
source ./lib/utils.sh

# ==================== FIRST-BOOT REGISTRATION ====================

users_file_exists() {
    [ -f "$USERS_FILE" ]
}

# Called only on first boot when no users.csv exists yet
register_first_user() {
    show_header
    echo "⚠️  First time setup required."
    echo ""
    echo "===== CREATE MANAGER ACCOUNT ====="
    echo ""

    while true; do
        read -p "Enter username (min 8 chars, alphanumeric): " username
        if validate_username "$username"; then
            if ! username_exists "$username"; then
                break
            else
                echo "Username already exists."
            fi
        fi
    done

    while true; do
        read -sp "Enter password (min 8 chars, 1 uppercase, 1 digit): " password
        echo ""
        if validate_password "$password"; then
            read -sp "Confirm password: " password_confirm
            echo ""
            if [ "$password" = "$password_confirm" ]; then
                break
            else
                echo "Passwords don't match. Try again."
            fi
        fi
    done

    local password_hash
    password_hash=$(hash_password "$password")
    local created_date
    created_date=$(get_date)
    local created_time
    created_time=$(get_time)

    init_csv_file "$USERS_FILE" "username,password_hash,created_date,created_time"

    local user_record="$username,$password_hash,$created_date,$created_time"
    append_csv "$USERS_FILE" "$user_record"

    echo ""
    echo "===== ACCOUNT CREATED ====="
    echo "Username: $username"
    echo "Created:  $created_date $created_time"
    echo ""

    CURRENT_USER="$username"
    log_action "REGISTRATION" "First-time user registered"

    pause_prompt
}

# ==================== ADD NEW USER ====================

# Called from main menu by an already-logged-in user
add_new_user() {
    show_header
    echo "===== CREATE NEW MANAGER ACCOUNT ====="
    echo "Type 'cancel' at any prompt to go back."
    echo ""

    while true; do
        read -p "Enter username (min 8 chars, alphanumeric): " username

        if [ "$username" = "cancel" ]; then
            echo "Operation cancelled."
            pause_prompt
            return
        fi

        if validate_username "$username"; then
            if ! username_exists "$username"; then
                break
            else
                echo "Username already exists."
            fi
        fi
    done

    while true; do
        read -sp "Enter password (min 8 chars, 1 uppercase, 1 digit): " password
        echo ""

        if [ "$password" = "cancel" ]; then
            echo "Operation cancelled."
            pause_prompt
            return
        fi

        if validate_password "$password"; then
            read -sp "Confirm password: " password_confirm
            echo ""
            if [ "$password" = "$password_confirm" ]; then
                break
            else
                echo "Passwords don't match. Try again."
            fi
        fi
    done

    local password_hash
    password_hash=$(hash_password "$password")
    local created_date
    created_date=$(get_date)
    local created_time
    created_time=$(get_time)

    local user_record="$username,$password_hash,$created_date,$created_time"
    append_csv "$USERS_FILE" "$user_record"

    echo ""
    echo "===== ACCOUNT CREATED ====="
    echo "Username: $username"
    echo "Created:  $created_date $created_time"
    echo ""

    log_action "USER_CREATED" "Added new user: $username"

    pause_prompt
}

# ==================== LOGIN ====================

# Returns 0 on success, 1 on failure.
# FIX: Removed pause_prompt from inside login_user so the caller (run_authentication)
#      controls flow and only one failure message is shown per attempt.
login_user() {
    show_header

    if ! users_file_exists; then
        echo "No user accounts found. Registration required."
        echo ""
        register_first_user
        return 0
    fi

    read -p "Username: " username
    read -sp "Password: " password
    echo ""

    if ! username_exists "$username"; then
        return 1
    fi

    local stored_hash
    stored_hash=$(grep "^$username," "$USERS_FILE" | awk -F',' '{print $2}')

    if verify_password "$password" "$stored_hash"; then
        CURRENT_USER="$username"
        log_action "LOGIN" "User logged in"
        return 0
    else
        return 1
    fi
}

logout_user() {
    log_action "LOGOUT" "User logged out"
    CURRENT_USER=""
}

# ==================== AUTHENTICATION LOOP ====================

# FIX: run_authentication now owns all failure messaging.
#      login_user no longer prints "Invalid credentials" or calls pause_prompt —
#      that prevented duplicate messages appearing on each failed attempt.
run_authentication() {
    local attempts=0
    local max_attempts=3

    while [ "$attempts" -lt "$max_attempts" ]; do
        if login_user; then
            return 0
        fi

        ((attempts++))

        if [ "$attempts" -lt "$max_attempts" ]; then
            echo ""
            echo "❌ Invalid credentials. Attempt $attempts of $max_attempts."
            pause_prompt
        fi
    done

    echo ""
    echo "❌ Maximum login attempts reached. Security lockout triggered."
    exit 1
}
