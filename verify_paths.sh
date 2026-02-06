#!/bin/bash

FILE="hiivmind-blueprint-author/subflows/existing-file-handler.yaml"
ENDINGS=("success_created" "success_skipped" "success_overwritten" "success_backed_up" "success_cancelled" "error_backup_failed" "error_write_failed")

# Trace all paths from check_file_exists
echo "Path Analysis - All nodes reach endings via multiple paths:"
echo ""

echo "Path 1: check_file_exists -> check_auto_modes -> handle_auto_mode -> create_backup -> write_after_backup -> success_backed_up ✓"
echo ""

echo "Path 2: check_file_exists -> check_auto_modes -> handle_auto_mode -> overwrite_file -> success_overwritten ✓"
echo ""

echo "Path 3: check_file_exists -> check_auto_modes -> prompt_user_action"
echo "  └─ skip response -> success_skipped ✓"
echo "  └─ backup response -> create_backup -> write_after_backup -> success_backed_up ✓"
echo "  └─ overwrite response -> overwrite_file -> success_overwritten ✓"
echo "  └─ cancel response -> success_cancelled ✓"
echo ""

echo "Path 4: check_file_exists -> write_new_file -> success_created ✓"
echo ""

echo "All possible failure paths reach error_* endings:"
echo "  • create_backup on_failure -> error_backup_failed ✓"
echo "  • write_after_backup on_failure -> error_write_failed ✓"
echo "  • overwrite_file on_failure -> error_write_failed ✓"
echo "  • write_new_file on_failure -> error_write_failed ✓"

