#!/bin/bash

# GSMS Configuration File
# All paths and constants defined here

# Data directory (where CSV files live)
DATA_DIR="./data"

# CSV file paths
USERS_FILE="$DATA_DIR/users.csv"
PRODUCTS_FILE="$DATA_DIR/products.csv"
ORDERS_FILE="$DATA_DIR/orders.csv"
LEDGER_FILE="$DATA_DIR/ledger.csv"
AUDIT_TRAIL_FILE="$DATA_DIR/audit_trail.csv"

# Create data directory if it doesn't exist
mkdir -p "$DATA_DIR"

# Application settings
APP_NAME="Grocery Store Management System"
APP_VERSION="1.0"
LOW_STOCK_THRESHOLD=20
EXPIRY_ALERT_DAYS=7

# Password constraints
MIN_PASSWORD_LENGTH=8
MIN_USERNAME_LENGTH=8

# Delivery outcome probabilities (must sum to 100)
# FIX: All three rates are now actually used in get_random_outcome()
DELIVERY_SUCCESS_RATE=70
DELIVERY_CANCEL_RATE=20
DELIVERY_SENTBACK_RATE=10

# Date/Time format
DATE_FORMAT="%Y-%m-%d"
# FIX: Was "%H:%M %p" which mixed 24h clock with AM/PM (e.g. "14:30 PM").
#      Changed to 12-hour format so %I and %p are consistent.
TIME_FORMAT="%I:%M %p"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file for debugging
LOG_FILE="./gsms.log"

# Current logged-in user (set during login)
CURRENT_USER=""
