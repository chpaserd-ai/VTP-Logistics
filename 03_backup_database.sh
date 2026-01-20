#!/bin/bash
# Enhanced database backup script
# Version: 2.0

set -euo pipefail

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_RETENTION_DAYS=30
COMPRESSION_LEVEL=6
ENCRYPT_BACKUPS=false  # Set to true and provide encryption password if needed

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

# Function to get database size
get_database_size() {
    local db_name="$1"
    
    MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "SELECT 
            ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as 'Size_MB'
            FROM information_schema.TABLES 
            WHERE table_schema = '${db_name}'
            GROUP BY table_schema;" --skip-column-names 2>/dev/null || echo "0"
}

# Function to create backup
create_backup() {
    local db_name="$1"
    local backup_dir="$2"
    local timestamp="$3"
    local backup_file="$4"
    
    log_info "Starting backup of database: $db_name"
    
    # Get database size
    local db_size
    db_size=$(get_database_size "$db_name")
    log_info "Database size: ${db_size}MB"
    
    # Create backup command
    local backup_cmd="MYSQL_PWD=\"${DB_PASSWORD}\" mysqldump --host=\"${DB_HOST}\" --port=\"${DB_PORT}\" --user=\"${DB_USER}\""
    
    # Add options
    backup_cmd+=" --single-transaction"
    backup_cmd+=" --routines"
    backup_cmd+=" --triggers"
    backup_cmd+=" --events"
    backup_cmd+=" --add-drop-database"
    backup_cmd+=" --databases \"${db_name}\""
    
    # Add table-specific excludes if needed
    # backup_cmd+=" --ignore-table=${db_name}.audit_log"
    
    # Execute backup
    log_info "Creating backup file..."
    local start_time=$(date +%s)
    
    if eval "$backup_cmd" 2>/tmp/backup_errors.log | gzip -c -${COMPRESSION_LEVEL} > "$backup_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local backup_size=$(du -h "$backup_file" | cut -f1)
        
        log_success "Backup completed in ${duration}s"
        log_success "Backup size: $backup_size"
        return 0
    else
        log_error "Backup failed"
        cat /tmp/backup_errors.log
        rm -f /tmp/backup_errors.log
        return 1
    fi
}

# Function to create backup metadata
create_backup_metadata() {
    local backup_file="$1"
    local metadata_file="${backup_file}.meta"
    
    cat > "$metadata_file" << EOF
BACKUP_METADATA_VERSION=1.0
BACKUP_DATE=$(date '+%Y-%m-%d %H:%M:%S')
BACKUP_FILE=$(basename "$backup_file")
DATABASE_NAME=${DB_NAME}
DATABASE_HOST=${DB_HOST}
DATABASE_PORT=${DB_PORT}
DATABASE_USER=${DB_USER}
BACKUP_SIZE=$(du -b "$backup_file" | cut -f1)
CHECKSUM=$(sha256sum "$backup_file" | cut -d' ' -f1)
COMPRESSION=gzip
COMPRESSION_LEVEL=${COMPRESSION_LEVEL}
ENCRYPTED=${ENCRYPT_BACKUPS}
EOF
    
    log_info "Metadata created: $(basename "$metadata_file")"
}

# Function to verify backup
verify_backup() {
    local backup_file="$1"
    
    log_info "Verifying backup integrity..."
    
    # Check if backup file exists and has content
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found"
        return 1
    fi
    
    local file_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null)
    if [[ $file_size -lt 1024 ]]; then
        log_error "Backup file seems too small: ${file_size} bytes"
        return 1
    fi
    
    # Test decompression
    if gzip -t "$backup_file" 2>/dev/null; then
        log_success "Backup file integrity verified"
        return 0
    else
        log_error "Backup file is corrupt or not valid gzip"
        return 1
    fi
}

# Function to clean old backups
clean_old_backups() {
    local backup_dir="$1"
    local retention_days="$2"
    
    log_info "Cleaning backups older than ${retention_days} days..."
    
    local files_deleted=0
    local space_freed=0
    
    # Find and delete old backup files
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            local file_size
            file_size=$(du -k "$file" | cut -f1)
            space_freed=$((space_freed + file_size))
            files_deleted=$((files_deleted + 1))
            
            rm -f "$file"
            # Also remove metadata file if it exists
            rm -f "${file}.meta"
        fi
    done < <(find "$backup_dir" -name "*.sql.gz" -mtime +"${retention_days}")
    
    if [[ $files_deleted -gt 0 ]]; then
        local space_freed_mb
        space_freed_mb=$((space_freed / 1024))
        log_success "Cleaned $files_deleted old backups, freed ${space_freed_mb}MB"
    else
        log_info "No old backups to clean"
    fi
}

# Function to display backup summary
display_backup_summary() {
    local backup_dir="$1"
    
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    BACKUP SUMMARY                       ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # List recent backups
    echo "Recent Backups:"
    echo "────────────────────────────────────────"
    
    local count=0
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            count=$((count + 1))
            local file_size
            file_size=$(du -h "$file" | cut -f1)
            local file_date
            file_date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
            local file_time
            file_time=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f2 | cut -d. -f1)
            
            printf "  %2d) %-50s %8s  %s %s\n" \
                "$count" \
                "$(basename "$file")" \
                "$file_size" \
                "$file_date" \
                "$file_time"
            
            # Show metadata if available
            local meta_file="${file}.meta"
            if [[ -f "$meta_file" ]]; then
                local checksum
                checksum=$(grep '^CHECKSUM=' "$meta_file" | cut -d'=' -f2 | head -c 16)
                printf "       Checksum: %s...\n" "$checksum"
            fi
        fi
    done < <(find "$backup_dir" -name "*.sql.gz" -type f | sort -r | head -10)
    
    if [[ $count -eq 0 ]]; then
        echo "  No backups found"
    fi
    
    # Show backup directory info
    echo ""
    echo "Backup Directory:"
    echo "────────────────────────────────────────"
    echo "  Location: $(realpath "$backup_dir")"
    
    local total_backups
    total_backups=$(find "$backup_dir" -name "*.sql.gz" -type f | wc -l)
    echo "  Total backups: $total_backups"
    
    local total_size
    total_size=$(find "$backup_dir" -name "*.sql.gz" -type f -exec du -ck {} + | tail -1 | cut -f1)
    local total_size_mb
    total_size_mb=$((total_size / 1024))
    echo "  Total size: ${total_size_mb}MB"
    
    # Show disk space
    echo ""
    echo "Disk Space:"
    echo "────────────────────────────────────────"
    df -h "$backup_dir" | tail -1 | awk '{print "  Available: " $4 " / " $2 " (" $5 " used)"}'
    
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     Database Backup Utility           ${NC}"
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
    
    echo "Database Configuration:"
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
    
    # Check if database exists
    local db_exists
    db_exists=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '${DB_NAME}';" --skip-column-names 2>/dev/null)
    
    if [[ "$db_exists" -ne 1 ]]; then
        log_error "Database '$DB_NAME' does not exist"
        exit 1
    fi
    
    # Create backup directory
    local backup_dir="../backups"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${backup_dir}/${DB_NAME}_backup_${timestamp}.sql.gz"
    
    mkdir -p "$backup_dir"
    log_info "Backup directory: $(realpath "$backup_dir")"
    
    # Create backup
    if ! create_backup "$DB_NAME" "$backup_dir" "$timestamp" "$backup_file"; then
        log_error "Backup failed"
        exit 1
    fi
    
    # Create metadata
    create_backup_metadata "$backup_file"
    
    # Verify backup
    if ! verify_backup "$backup_file"; then
        log_error "Backup verification failed"
        # Don't exit, just warn
    fi
    
    # Clean old backups
    clean_old_backups "$backup_dir" "$BACKUP_RETENTION_DAYS"
    
    # Display summary
    display_backup_summary "$backup_dir"
    
    # Clean up
    unset DB_PASSWORD
    rm -f /tmp/backup_errors.log 2>/dev/null
    
    log_success "Backup process completed successfully!"
}

# Execute main function
main "$@"