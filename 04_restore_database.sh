#!/bin/bash
# Enhanced database restore script
# Version: 2.0

set -euo pipefail

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment safely
load_environment() {
    local env_file="${1:-../backend/.env}"
    
    if [[ -f "$env_file" ]]; then
        echo "Loading environment variables from $env_file..."
        
        # Clear existing database variables
        unset DB_USER DB_PASSWORD DB_NAME DB_HOST DB_PORT
        
        # Read .env line by line safely
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z $key ]] && continue
            
            # Remove quotes if present
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            
            # Export variable
            export "$key"="$value"
        done < <(grep -v '^#' "$env_file")
        
        return 0
    else
        echo "No .env file found at $env_file"
        return 1
    fi
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to list available backups
list_backups() {
    local backup_dir="$1"
    
    echo ""
    echo "Available Backups:"
    echo "────────────────────────────────────────"
    
    local i=1
    declare -A backup_files
    
    # Find backup files
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            backup_files[$i]="$file"
            
            local file_size
            file_size=$(du -h "$file" | cut -f1)
            local file_date
            file_date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
            local file_time
            file_time=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f2 | cut -d. -f1)
            
            # Try to get database name from metadata
            local meta_file="${file}.meta"
            local db_name="Unknown"
            if [[ -f "$meta_file" ]]; then
                db_name=$(grep '^DATABASE_NAME=' "$meta_file" | cut -d'=' -f2)
            fi
            
            printf "  %2d) %-50s\n" "$i" "$(basename "$file")"
            printf "       Database: %-30s Size: %8s\n" "$db_name" "$file_size"
            printf "       Date: %s %s\n" "$file_date" "$file_time"
            
            ((i++))
        fi
    done < <(find "$backup_dir" -name "*.sql.gz" -type f | sort -r)
    
    # Also list uncompressed backups
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            backup_files[$i]="$file"
            
            local file_size
            file_size=$(du -h "$file" | cut -f1)
            local file_date
            file_date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
            local file_time
            file_time=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f2 | cut -d. -f1)
            
            printf "  %2d) %-50s\n" "$i" "$(basename "$file")"
            printf "       [UNCOMPRESSED] Size: %8s\n" "$file_size"
            printf "       Date: %s %s\n" "$file_date" "$file_time"
            
            ((i++))
        fi
    done < <(find "$backup_dir" -name "*.sql" -type f | sort -r)
    
    echo "────────────────────────────────────────"
    
    if [[ $i -eq 1 ]]; then
        log_error "No backup files found in $backup_dir"
        return 1
    fi
    
    echo ""
    return 0
}

# Function to verify backup file
verify_backup_file() {
    local backup_file="$1"
    
    log_info "Verifying backup file..."
    
    # Check if file exists
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    # Check file size
    local file_size
    file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
    if [[ $file_size -lt 1024 ]]; then
        log_error "Backup file is too small: ${file_size} bytes"
        return 1
    fi
    
    # Check if it's compressed
    if [[ "$backup_file" == *.gz ]]; then
        if ! gzip -t "$backup_file" 2>/dev/null; then
            log_error "Backup file is corrupt (gzip test failed)"
            return 1
        fi
    fi
    
    # Check metadata if available
    local meta_file="${backup_file}.meta"
    if [[ -f "$meta_file" ]]; then
        log_info "Found backup metadata"
        
        # Verify checksum
        local expected_checksum
        expected_checksum=$(grep '^CHECKSUM=' "$meta_file" | cut -d'=' -f2)
        local actual_checksum
        actual_checksum=$(sha256sum "$backup_file" | cut -d' ' -f1)
        
        if [[ "$expected_checksum" == "$actual_checksum" ]]; then
            log_success "Checksum verification passed"
        else
            log_warning "Checksum verification failed (file may be modified)"
            echo "  Expected: ${expected_checksum:0:16}..."
            echo "  Actual:   ${actual_checksum:0:16}..."
            
            read -p "Continue anyway? (yes/no): " continue_choice
            if [[ "$continue_choice" != "yes" ]]; then
                return 1
            fi
        fi
    else
        log_warning "No metadata found for backup"
    fi
    
    return 0
}

# Function to extract backup content info
get_backup_info() {
    local backup_file="$1"
    local temp_dir="$2"
    
    log_info "Analyzing backup content..."
    
    # Decompress if needed
    if [[ "$backup_file" == *.gz ]]; then
        local temp_file="${temp_dir}/backup.sql"
        gunzip -c "$backup_file" > "$temp_file"
    else
        local temp_file="$backup_file"
    fi
    
    # Extract database name from backup
    local db_name_in_backup
    db_name_in_backup=$(grep -m1 "CREATE DATABASE" "$temp_file" 2>/dev/null | sed -n "s/.*\`\([^`]*\)\`.*/\1/p" || echo "")
    
    # Count tables in backup
    local table_count
    table_count=$(grep -c "CREATE TABLE" "$temp_file" 2>/dev/null || echo "0")
    
    # Get backup date from file name or metadata
    local backup_date
    if [[ -f "${backup_file}.meta" ]]; then
        backup_date=$(grep '^BACKUP_DATE=' "${backup_file}.meta" | cut -d'=' -f2)
    else
        backup_date=$(stat -c %y "$backup_file" 2>/dev/null | cut -d' ' -f1)
    fi
    
    # Clean up temp file
    if [[ "$backup_file" == *.gz" ]] && [[ -f "$temp_file" ]]; then
        rm -f "$temp_file"
    fi
    
    echo "$db_name_in_backup $table_count $backup_date"
}

# Function to create pre-restore backup
create_pre_restore_backup() {
    local db_name="$1"
    local backup_dir="$2"
    
    log_info "Creating backup of current database..."
    
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${backup_dir}/pre_restore_${db_name}_${timestamp}.sql.gz"
    
    if MYSQL_PWD="${DB_PASSWORD}" mysqldump --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --databases "$db_name" 2>/dev/null | gzip > "$backup_file"; then
        
        local backup_size
        backup_size=$(du -h "$backup_file" | cut -f1)
        log_success "Pre-restore backup created: $(basename "$backup_file") ($backup_size)"
        echo "  Location: $(realpath "$backup_file")"
        
        return 0
    else
        log_error "Failed to create pre-restore backup"
        return 1
    fi
}

# Function to restore database
restore_database() {
    local backup_file="$1"
    local target_db="$2"
    local temp_dir="$3"
    
    log_info "Starting database restore..."
    
    # Decompress backup if needed
    local source_file
    if [[ "$backup_file" == *.gz ]]; then
        source_file="${temp_dir}/restore.sql"
        log_info "Decompressing backup..."
        
        if ! gunzip -c "$backup_file" > "$source_file"; then
            log_error "Failed to decompress backup"
            return 1
        fi
    else
        source_file="$backup_file"
    fi
    
    # Get database name from backup
    local backup_db_name
    backup_db_name=$(grep -m1 "CREATE DATABASE" "$source_file" 2>/dev/null | sed -n "s/.*\`\([^`]*\)\`.*/\1/p" || echo "")
    
    # Replace database name in backup file if different from target
    if [[ -n "$backup_db_name" ]] && [[ "$backup_db_name" != "$target_db" ]]; then
        log_info "Adjusting database name from '$backup_db_name' to '$target_db'"
        
        local adjusted_file="${temp_dir}/adjusted_backup.sql"
        sed "s/\`${backup_db_name}\`/\`${target_db}\`/g" "$source_file" > "$adjusted_file"
        source_file="$adjusted_file"
    fi
    
    # Drop and recreate database
    log_info "Preparing database..."
    
    if ! MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "DROP DATABASE IF EXISTS \`${target_db}\`;"; then
        log_error "Failed to drop database"
        return 1
    fi
    
    if ! MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "CREATE DATABASE \`${target_db}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
        log_error "Failed to create database"
        return 1
    fi
    
    # Restore data
    log_info "Restoring data..."
    local start_time=$(date +%s)
    
    if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$target_db" < "$source_file"; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "Database restored in ${duration}s"
        
        # Clean up temp files
        rm -f "${temp_dir}/restore.sql" "${temp_dir}/adjusted_backup.sql" 2>/dev/null
        
        return 0
    else
        log_error "Failed to restore database"
        # Don't clean temp files for debugging
        return 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     Database Restore Utility          ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Load environment variables
    if ! load_environment; then
        log_warning "Using default configuration"
        DB_USER="${DB_USER:-root}"
        DB_PASSWORD="${DB_PASSWORD:-}"
        DB_NAME="${DB_NAME:-logistics_platform}"
        DB_HOST="${DB_HOST:-localhost}"
        DB_PORT="${DB_PORT:-3306}"
    else
        # Set defaults if not in .env
        DB_USER="${DB_USER:-root}"
        DB_PASSWORD="${DB_PASSWORD:-}"
        DB_NAME="${DB_NAME:-logistics_platform}"
        DB_HOST="${DB_HOST:-localhost}"
        DB_PORT="${DB_PORT:-3306}"
    fi
    
    echo "Target Database Configuration:"
    echo "  Host:     $DB_HOST:$DB_PORT"
    echo "  Database: $DB_NAME"
    echo "  User:     $DB_USER"
    echo ""
    
    # Test MySQL connection
    log_info "Testing database connection..."
    if ! MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        --connect-timeout=10 -e "SELECT 1;" >/dev/null 2>&1; then
        log_error "Cannot connect to MySQL"
        exit 1
    fi
    
    log_success "Connected to MySQL"
    
    # List available backups
    local backup_dir="../backups"
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory not found: $backup_dir"
        exit 1
    fi
    
    if ! list_backups "$backup_dir"; then
        exit 1
    fi
    
    # Select backup
    echo ""
    read -p "Select backup number: " selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        log_error "Invalid selection"
        exit 1
    fi
    
    # Get selected backup file
    local backup_files=()
    local i=1
    
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            backup_files[$i]="$file"
            ((i++))
        fi
    done < <(find "$backup_dir" -name "*.sql.gz" -type f | sort -r)
    
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            backup_files[$i]="$file"
            ((i++))
        fi
    done < <(find "$backup_dir" -name "*.sql" -type f | sort -r)
    
    if [[ -z "${backup_files[$selection]}" ]]; then
        log_error "Invalid selection"
        exit 1
    fi
    
    local selected_backup="${backup_files[$selection]}"
    echo ""
    log_info "Selected backup: $(basename "$selected_backup")"
    
    # Verify backup file
    if ! verify_backup_file "$selected_backup"; then
        exit 1
    fi
    
    # Get backup info
    local temp_dir
    temp_dir=$(mktemp -d)
    local backup_info
    backup_info=$(get_backup_info "$selected_backup" "$temp_dir")
    read -r backup_db_name table_count backup_date <<< "$backup_info"
    
    echo ""
    echo "Backup Information:"
    echo "────────────────────────────────────────"
    echo "  Original database: ${backup_db_name:-Unknown}"
    echo "  Tables in backup:  $table_count"
    echo "  Backup date:       ${backup_date:-Unknown}"
    echo "  Target database:   $DB_NAME"
    echo ""
    
    # Confirm restore
    echo -e "${YELLOW}⚠️  RESTORE CONFIRMATION REQUIRED${NC}"
    echo "────────────────────────────────────────"
    echo "This operation will:"
    echo "  1. Create backup of current database"
    echo "  2. Drop database: $DB_NAME"
    echo "  3. Restore from selected backup"
    echo "  4. All current data will be lost!"
    echo ""
    
    read -p "Type 'RESTORE' to confirm: " confirm
    if [[ "$confirm" != "RESTORE" ]]; then
        log_info "Restore cancelled"
        rm -rf "$temp_dir"
        exit 0
    fi
    
    # Create pre-restore backup
    if ! create_pre_restore_backup "$DB_NAME" "$backup_dir"; then
        read -p "Continue without pre-restore backup? (yes/no): " continue_choice
        if [[ "$continue_choice" != "yes" ]]; then
            log_info "Restore cancelled"
            rm -rf "$temp_dir"
            exit 0
        fi
    fi
    
    # Restore database
    if restore_database "$selected_backup" "$DB_NAME" "$temp_dir"; then
        log_success "✅ Database restore completed successfully!"
        
        # Verify restore
        log_info "Verifying restore..."
        local restored_tables
        restored_tables=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | wc -l)
        
        echo ""
        echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}                    RESTORE COMPLETE                     ${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Restore Summary:"
        echo "────────────────────────────────────────"
        echo "  Source backup:   $(basename "$selected_backup")"
        echo "  Target database: $DB_NAME"
        echo "  Tables restored: $restored_tables"
        echo ""
        echo "Next steps:"
        echo "  1. Verify application functionality"
        echo "  2. Test user logins"
        echo "  3. Check critical data"
        echo ""
    else
        log_error "❌ Database restore failed"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check pre-restore backup in $backup_dir"
        echo "  2. Verify backup file integrity"
        echo "  3. Check MySQL error logs"
        echo ""
        exit 1
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    unset DB_PASSWORD
    
    log_info "Restore process completed"
}

# Execute main function
main "$@"