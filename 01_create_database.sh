#!/bin/bash
# Database creation script - Enhanced with security features
# Version: 2.0

set -euo pipefail

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

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Function to check MySQL connection
check_mysql_connection() {
    local user="$1"
    local password="$2"
    local host="$3"
    local port="$4"
    
    # Hide password from process list
    MYSQL_PWD="${password}" mysql --host="$host" --port="$port" --user="$user" \
        --connect-timeout=10 \
        -e "SELECT 1;" >/dev/null 2>&1
}

# Function to get MySQL version
get_mysql_version() {
    MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "SELECT VERSION();" --skip-column-names 2>/dev/null || echo "Unknown"
}

# Function to check if database exists
database_exists() {
    local db_name="$1"
    local exists
    
    exists=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '${db_name}';" --skip-column-names 2>/dev/null)
    
    [[ "$exists" -eq 1 ]]
}

# Function to backup existing database
backup_existing_database() {
    local db_name="$1"
    local backup_dir="../backups"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${backup_dir}/${db_name}_pre_init_${timestamp}.sql.gz"
    
    log_info "Checking for existing database..."
    
    if database_exists "$db_name"; then
        log_warning "Database '$db_name' already exists!"
        echo ""
        echo "Options:"
        echo "  1) Backup and replace (recommended)"
        echo "  2) Skip initialization"
        echo "  3) Exit"
        echo ""
        
        read -p "Enter choice [1/2/3]: " choice
        
        case $choice in
            1)
                mkdir -p "$backup_dir"
                log_info "Creating backup of existing database..."
                
                if MYSQL_PWD="${DB_PASSWORD}" mysqldump --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
                    --single-transaction \
                    --routines \
                    --triggers \
                    --events \
                    "$db_name" 2>/dev/null | gzip > "$backup_file"; then
                    log_success "Backup created: $(basename "$backup_file")"
                    return 0
                else
                    log_error "Failed to create backup"
                    return 1
                fi
                ;;
            2)
                log_info "Skipping database initialization"
                exit 0
                ;;
            3|*)
                log_info "Exiting..."
                exit 0
                ;;
        esac
    fi
    
    return 0
}

# Function to check required tools
check_required_tools() {
    local missing_tools=()
    
    for tool in mysql mysqldump gzip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install them using your package manager:"
        echo "  Ubuntu/Debian: sudo apt-get install mysql-client"
        echo "  RHEL/CentOS: sudo yum install mysql"
        echo "  macOS: brew install mysql-client"
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    Logistics Platform Database Setup    ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Check required tools
    log_info "Checking system requirements..."
    check_required_tools || exit 1
    
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
    
    echo ""
    echo "Database Configuration:"
    echo "  Host:     $DB_HOST:$DB_PORT"
    echo "  Database: $DB_NAME"
    echo "  User:     $DB_USER"
    echo ""
    
    # Test MySQL connection
    log_info "Testing database connection..."
    if check_mysql_connection "$DB_USER" "$DB_PASSWORD" "$DB_HOST" "$DB_PORT"; then
        mysql_version=$(get_mysql_version)
        log_success "Connected to MySQL $mysql_version"
    else
        log_error "Cannot connect to MySQL"
        echo ""
        echo "Troubleshooting steps:"
        echo "  1. Ensure MySQL/MariaDB is running"
        echo "  2. Check credentials in .env file"
        echo "  3. Verify network connectivity"
        echo "  4. Check firewall settings"
        echo ""
        echo "Quick checks:"
        echo "  MySQL service: sudo systemctl status mysql"
        echo "  Test connection: mysql -u $DB_USER -p -h $DB_HOST -P $DB_PORT"
        exit 1
    fi
    
    # Check for existing database
    backup_existing_database "$DB_NAME"
    
    # Check if init.sql exists
    local init_script="init.sql"
    if [[ ! -f "$init_script" ]]; then
        log_error "Initialization script '$init_script' not found!"
        echo "Current directory: $(pwd)"
        echo "Please ensure init.sql is in the same directory"
        exit 1
    fi
    
    # Create database
    log_info "Creating database '$DB_NAME'..."
    if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
        log_success "Database created successfully"
    else
        log_error "Failed to create database"
        exit 1
    fi
    
    # Run initialization script
    log_info "Running initialization script..."
    local start_time=$(date +%s)
    
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
    
    # Verify setup
    log_info "Verifying database setup..."
    
    # Count tables
    local table_count
    table_count=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | wc -l)
    
    if [[ $table_count -gt 0 ]]; then
        log_success "Found $table_count tables"
        
        # Get sample data counts
        local user_count customer_count warehouse_count vehicle_count
        
        user_count=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "SELECT COUNT(*) FROM users;" --skip-column-names 2>/dev/null)
        
        customer_count=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "SELECT COUNT(*) FROM customers;" --skip-column-names 2>/dev/null)
        
        warehouse_count=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "SELECT COUNT(*) FROM warehouses;" --skip-column-names 2>/dev/null)
        
        vehicle_count=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "SELECT COUNT(*) FROM vehicles;" --skip-column-names 2>/dev/null)
        
        echo ""
        echo "Sample Data Summary:"
        echo "  ┌─────────────────┬───────┐"
        echo "  │ Users           │ $user_count │"
        echo "  │ Customers       │ $customer_count │"
        echo "  │ Warehouses      │ $warehouse_count │"
        echo "  │ Vehicles        │ $vehicle_count │"
        echo "  └─────────────────┴───────┘"
    else
        log_warning "No tables found in database"
    fi
    
    # Test database functionality
    log_info "Testing database functionality..."
    
    # Test tracking number generation
    local test_tracking
    test_tracking=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" -e "CALL generate_tracking_number(@tracking); SELECT @tracking;" --skip-column-names 2>/dev/null)
    
    if [[ -n "$test_tracking" ]]; then
        log_success "Tracking number generation: $test_tracking"
    fi
    
    # Test views
    local view_count
    view_count=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" -e "SELECT COUNT(*) FROM information_schema.views WHERE table_schema = '${DB_NAME}';" --skip-column-names 2>/dev/null)
    
    log_success "Created $view_count views"
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ Database Setup Completed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # Security warning
    echo -e "${YELLOW}⚠️  IMPORTANT SECURITY NOTES:${NC}"
    echo "────────────────────────────────────────"
    echo "1. Default passwords are set for development only"
    echo "2. You MUST change all passwords before production use"
    echo ""
    echo "Application users (password: admin123):"
    echo "  • admin     - Full system access"
    echo "  • manager1  - Management access"
    echo "  • driver1   - Driver access"
    echo "  • staff1    - Staff access"
    echo ""
    echo "Database users:"
    echo "  • logistics_app     - Application user"
    echo "  • logistics_backup  - Backup user"
    echo "  • logistics_report  - Report user"
    echo ""
    
    # Next steps
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo "────────────────────────────────────────"
    echo "1. Change database user passwords:"
    echo "   mysql> ALTER USER 'logistics_app'@'localhost' IDENTIFIED BY 'NewStrongPassword123!';"
    echo ""
    echo "2. Change application user passwords:"
    echo "   ./update_admin_password.sh"
    echo ""
    echo "3. Start the application:"
    echo "   cd ../backend && npm start"
    echo ""
    echo "4. Access the system:"
    echo "   Frontend: http://localhost:8080"
    echo "   Backend API: http://localhost:3000"
    echo ""
    
    # Quick commands
    echo -e "${BLUE}📚 Useful Commands:${NC}"
    echo "────────────────────────────────────────"
    echo "  make backup    - Create database backup"
    echo "  make restore   - Restore from backup"
    echo "  make check     - Check database health"
    echo "  make reset     - Reset database (CAUTION)"
    echo "  make secure    - Run security hardening"
    echo ""
    
    # Clean up environment variables
    unset DB_PASSWORD
    log_info "Setup completed. Environment variables cleared."
}

# Execute main function with error handling
main "$@"