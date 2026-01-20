#!/bin/bash
# Central configuration for database scripts
# Version: 2.0

set -euo pipefail

# ============================================
# COLOR DEFINITIONS
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Bold colors
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'

# ============================================
# LOGGING FUNCTIONS
# ============================================
LOG_DIR="../logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/database_$(date +%Y%m%d).log"

log_message() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "$message" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log_message "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log_message "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log_message "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log_message "${CYAN}[DEBUG]${NC} $1"
    fi
}

# ============================================
# ENVIRONMENT LOADING
# ============================================
load_environment() {
    local env_file="${1:-../backend/.env}"
    
    if [[ -f "$env_file" ]]; then
        log_debug "Loading environment from $env_file"
        
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
            log_debug "  Set $key=***"
        done < <(grep -v '^#' "$env_file")
        
        log_success "Environment loaded from $env_file"
        return 0
    else
        log_warning "No .env file found at $env_file"
        return 1
    fi
}

# ============================================
# DATABASE CONFIGURATION
# ============================================
# Default values
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-logistics_platform}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"

# Backup configuration
BACKUP_DIR="../backups"
BACKUP_RETENTION_DAYS=30
BACKUP_COMPRESSION_LEVEL=6

# Security configuration
SECURE_PASSWORD_LENGTH=16
BCRYPT_SALT_ROUNDS=10

# ============================================
# HELPER FUNCTIONS
# ============================================

# Safe MySQL execution
mysql_exec() {
    local query="$1"
    local options="${2:-}"
    local db="${3:-$DB_NAME}"
    
    log_debug "Executing MySQL query: ${query:0:100}..."
    
    MYSQL_PWD="$DB_PASSWORD" mysql \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --user="$DB_USER" \
        --silent \
        --skip-column-names \
        $options \
        "$db" \
        -e "$query" 2>> "$LOG_FILE"
}

# Safe MySQL command (for non-query operations)
mysql_cmd() {
    local command="$1"
    
    log_debug "Executing MySQL command: $command"
    
    MYSQL_PWD="$DB_PASSWORD" mysql \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --user="$DB_USER" \
        -e "$command" 2>> "$LOG_FILE"
}

# Check MySQL connection
check_mysql_connection() {
    log_info "Testing MySQL connection..."
    
    if mysql_cmd "SELECT 1;" >/dev/null 2>&1; then
        log_success "Connected to MySQL"
        
        # Get MySQL version
        local version
        version=$(mysql_exec "SELECT VERSION();")
        log_info "MySQL version: $version"
        
        return 0
    else
        log_error "Cannot connect to MySQL"
        return 1
    fi
}

# Check if database exists
database_exists() {
    local db_name="${1:-$DB_NAME}"
    
    local exists
    exists=$(mysql_exec "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '${db_name}';" "" "")
    
    [[ "$exists" -eq 1 ]]
}

# Get database size
get_database_size() {
    local db_name="${1:-$DB_NAME}"
    
    mysql_exec "SELECT 
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as size_mb
        FROM information_schema.tables 
        WHERE table_schema = '${db_name}'
        GROUP BY table_schema;" "" ""
}

# Get table count
get_table_count() {
    local db_name="${1:-$DB_NAME}"
    
    mysql_exec "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${db_name}';" "" ""
}

# ============================================
# SECURITY FUNCTIONS
# ============================================

# Generate secure password
generate_secure_password() {
    local length="${1:-$SECURE_PASSWORD_LENGTH}"
    
    # Try different password generation methods
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' | head -c "$length"
    elif command -v pwgen >/dev/null 2>&1; then
        pwgen -s "$length" 1
    elif [[ -f /dev/urandom ]]; then
        tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length"
    else
        # Fallback
        date +%s%N | sha256sum | base64 | head -c "$length"
    fi
    echo ""
}

# Mask sensitive output
mask_sensitive() {
    local text="$1"
    echo "$text" | sed 's/\(password\|secret\|key\|token\)[^=]*=[^ ]*/&/g' | \
        sed 's/\(password\|secret\|key\|token\)[^=]*=.*/\1=********/gi'
}

# ============================================
# VALIDATION FUNCTIONS
# ============================================

# Validate MySQL credentials
validate_mysql_credentials() {
    if [[ -z "$DB_USER" ]]; then
        log_error "Database user not set"
        return 1
    fi
    
    if [[ -z "$DB_HOST" ]]; then
        log_error "Database host not set"
        return 1
    fi
    
    return 0
}

# Validate database name
validate_database_name() {
    local db_name="$1"
    
    if [[ -z "$db_name" ]]; then
        log_error "Database name cannot be empty"
        return 1
    fi
    
    if ! [[ "$db_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_error "Invalid database name: $db_name"
        return 1
    fi
    
    return 0
}

# ============================================
# BACKUP FUNCTIONS
# ============================================

# Initialize backup directory
init_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    log_info "Backup directory: $(realpath "$BACKUP_DIR")"
}

# Clean old backups
clean_old_backups() {
    local retention_days="${1:-$BACKUP_RETENTION_DAYS}"
    
    log_info "Cleaning backups older than $retention_days days..."
    
    local deleted_count=0
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            # Also remove metadata file
            rm -f "${file}.meta" 2>/dev/null
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "$BACKUP_DIR" -name "*.sql.gz" -mtime +"$retention_days")
    
    if [[ $deleted_count -gt 0 ]]; then
        log_success "Cleaned $deleted_count old backups"
    else
        log_info "No old backups to clean"
    fi
}

# ============================================
# UI/UX FUNCTIONS
# ============================================

# Print header
print_header() {
    local title="$1"
    local color="${2:-BLUE}"
    
    eval "local color_code=\$$color"
    
    echo ""
    echo -e "${color_code}========================================${NC}"
    echo -e "${color_code}    $title${NC}"
    echo -e "${color_code}========================================${NC}"
    echo ""
}

# Print section
print_section() {
    local title="$1"
    
    echo ""
    echo -e "${CYAN}$title${NC}"
    echo "────────────────────────────────────────"
}

# Print success message
print_success() {
    local message="$1"
    echo -e "${GREEN}✅ $message${NC}"
}

# Print error message
print_error() {
    local message="$1"
    echo -e "${RED}❌ $message${NC}"
}

# Print warning message
print_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️  $message${NC}"
}

# ============================================
# EXPORT FUNCTIONS
# ============================================

# Export functions that should be available to other scripts
export -f log_message log_info log_success log_warning log_error log_debug
export -f load_environment
export -f mysql_exec mysql_cmd
export -f check_mysql_connection database_exists get_database_size get_table_count
export -f generate_secure_password mask_sensitive
export -f validate_mysql_credentials validate_database_name
export -f init_backup_dir clean_old_backups
export -f print_header print_section print_success print_error print_warning

# Export variables
export RED GREEN YELLOW BLUE CYAN MAGENTA NC
export BOLD_RED BOLD_GREEN BOLD_YELLOW BOLD_BLUE
export LOG_DIR LOG_FILE
export BACKUP_DIR BACKUP_RETENTION_DAYS BACKUP_COMPRESSION_LEVEL
export SECURE_PASSWORD_LENGTH BCRYPT_SALT_ROUNDS

log_debug "Configuration loaded successfully"