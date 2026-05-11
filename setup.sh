#!/bin/bash

# GSMS Setup Script
# Run this once before launching the application.
# FIX: chmod was previously called inside startup() on every run — moved here
#      where it belongs (one-time setup, not application logic).

echo "Setting up GSMS..."

# Make all scripts executable
chmod +x gsms.sh
chmod +x lib/*.sh
chmod +x config/*.sh

# Create data directory
mkdir -p ./data

echo "✓ Permissions set."
echo "✓ Data directory ready."
echo ""
echo "Run the application with:  bash gsms.sh"
echo ""
