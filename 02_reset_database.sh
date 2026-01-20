#!/bin/bash
# Database reset script - Enhanced with security features
# Version: 2.0
# WARNING: This will delete ALL data!

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

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

# Function to check MySQL connection
check_mysql_connection() {
    local user="$1"
    local password="$2"
    local host="$3"
    local port="$4"
    
    MYSQL_PWD="${password}" mysql --host="$host" --port="$port" --user="$user" \
        --connect-timeout=10 \
        -e "SELECT 1;" >/dev/null 2>&1
}

# Function to create backup
create_backup() {
    local db_name="$1"
    local backup_dir="../backups/reset_backups"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${backup_dir}/${db_name}_before_reset_${timestamp}.sql.gz"
    
    log_info "Creating backup before reset..."
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Create backup
    if MYSQL_PWD="${DB_PASSWORD}" mysqldump --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --add-drop-database \
        --databases "$db_name" 2>/dev/null | gzip > "$backup_file"; then
        
        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_success "Backup created: $(basename "$backup_file") ($backup_size)"
        
        # Show backup location
        echo "Backup saved to: $(realpath "$backup_file")"
        
        return 0
    else
        log_error "Failed to create backup"
        return 1
    fi
}

# Function to verify database exists
database_exists() {
    local db_name="$1"
    local exists
    
    exists=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '${db_name}';" --skip-column-names 2>/dev/null)
    
    [[ "$exists" -eq 1 ]]
}

# Function to get database size
get_database_size() {
    local db_name="$1"
    
    MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "SELECT 
            ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as 'Size (MB)',
            COUNT(*) as 'Tables'
            FROM information_schema.TABLES 
            WHERE table_schema = '${db_name}'
            GROUP BY table_schema;" --skip-column-names 2>/dev/null || echo "0 0"
}

# Function to confirm reset
confirm_reset() {
    local db_name="$1"
    
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${BOLD}                    ⚠️  DANGER: RESET DATABASE ⚠️                    ${NC}${RED}║${NC}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║${NC}                                                              ${RED}║${NC}"
    echo -e "${RED}║${NC}  This operation will:                                        ${RED}║${NC}"
    echo -e "${RED}║${NC}  1. Delete ALL data from database: ${BOLD}$db_name${NC}                ${RED}║${NC}"
    echo -e "${RED}║${NC}  2. Drop and recreate the database                           ${RED}║${NC}"
    echo -e "${RED}║${NC}  3. Restore initial sample data                              ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                              ${RED}║${NC}"
    echo -e "${RED}║${NC}  ${BOLD}THIS ACTION IS IRREVERSIBLE!${NC}                                ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                              ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get database size info
    local db_info
    db_info=$(get_database_size "$db_name")
    if [[ -n "$db_info" ]]; then
        read -r size tables <<< "$db_info"
        echo "Database Statistics:"
        echo "  • Tables: $tables"
        echo "  • Size: $size MB"
        echo ""
    fi
    
    # Multiple confirmation levels
    echo -e "${YELLOW}Level 1: Type the database name to confirm${NC}"
    read -p "Type '$db_name' to continue: " confirm1
    
    if [[ "$confirm1" != "$db_name" ]]; then
        log_info "Reset cancelled (incorrect database name)"
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Level 2: Type 'RESET' in uppercase${NC}"
    read -p "Type 'RESET' to continue: " confirm2
    
    if [[ "$confirm2" != "RESET" ]]; then
        log_info "Reset cancelled (missing RESET confirmation)"
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Level 3: Final confirmation${NC}"
    read -p "Are you absolutely sure? Type 'YES I AM SURE': " confirm3
    
    if [[ "$confirm3" != "YES I AM SURE" ]]; then
        log_info "Reset cancelled (final confirmation failed)"
        exit 0
    fi
    
    echo ""
    log_warning "Proceeding with database reset..."
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     Database Reset Utility            ${NC}"
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
    if ! check_mysql_connection "$DB_USER" "$DB_PASSWORD" "$DB_HOST" "$DB_PORT"; then
        log_error "Cannot connect to MySQL"
        exit 1
    fi
    
    log_success "Connected to MySQL"
    
    # Check if database exists
    if ! database_exists "$DB_NAME"; then
        log_error "Database '$DB_NAME' does not exist"
        log_info "Run ./01_create_database.sh first"
        exit 1
    fi
    
    # Show current database status
    log_info "Current database status..."
    local db_info
    db_info=$(get_database_size "$DB_NAME")
    if [[ -n "$db_info" ]]; then
        read -r size tables <<< "$db_info"
        echo "  • Tables: $tables"
        echo "  • Size: $size MB"
    fi
    
    # Confirm reset
    confirm_reset "$DB_NAME"
    
    # Create backup
    if ! create_backup "$DB_NAME"; then
        echo ""
        read -p "Backup failed. Continue with reset anyway? (yes/no): " continue_choice
        if [[ "$continue_choice" != "yes" ]]; then
            log_info "Reset cancelled due to backup failure"
            exit 0
        fi
        log_warning "Proceeding without backup"
    fi
    
    # Reset database
    log_info "Resetting database '$DB_NAME'..."
    local start_time=$(date +%s)
    
    # Drop and recreate database
    log_info "1. Dropping database..."
    if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"; then
        log_success "Database dropped"
    else
        log_error "Failed to drop database"
        exit 1
    fi
    
    log_info "2. Creating new database..."
    if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
        log_success "Database created"
    else
        log_error "Failed to create database"
        exit 1
    fi
    
    # Check if init.sql exists
    local init_script="init.sql"
    if [[ ! -f "$init_script" ]]; then
        log_error "Initialization script '$init_script' not found!"
        exit 1
    fi
    
    log_info "3. Running initialization script..."
    if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" < "$init_script"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "Database initialized in ${duration}s"
    else
        log_error "Failed to initialize database"
        log_info "Check for SQL errors in $init_script"
        exit 1
    fi
    
    # Verify reset
    log_info "Verifying reset..."
    
    # Count tables
    local table_count
    table_count=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | wc -l)
    
    if [[ $table_count -gt 0 ]]; then
        log_success "Database reset complete: $table_count tables created"
        
        # Verify sample data
        local user_count
        user_count=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "SELECT COUNT(*) FROM users;" --skip-column-names 2>/dev/null)
        
        echo ""
        echo -e "${GREEN}✅ Database Reset Completed!${NC}"
        echo ""
        echo "Default credentials restored:"
        echo "  Username: admin"
        echo "  Password: admin123"
        echo ""
        echo -e "${YELLOW}⚠️  IMPORTANT: Change the admin password immediately!${NC}"
        echo ""
        echo "To change password:"
        echo "  ./update_admin_password.sh"
        echo ""
    else
        log_error "Reset failed - no tables found"
        exit 1
    fi
    
    # Clean up environment variables
    unset DB_PASSWORD
    log_info "Environment variables cleared"
}

# Execute main function
main "$@"