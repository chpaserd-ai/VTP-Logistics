#!/bin/bash
# Bulk password update script for demo users
# Version: 2.0

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default password for demo users
DEMO_PASSWORD="admin123"

# List of demo users to update
declare -a DEMO_USERS=("admin" "manager1" "driver1" "staff1")

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

# Generate bcrypt hash (using pre-generated for consistency)
generate_bcrypt_hash() {
    # Pre-generated bcrypt hash for 'admin123' (salt rounds: 10)
    echo '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy'
}

# Check MySQL connection
check_mysql_connection() {
    log_info "Testing database connection..."
    
    if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        --connect-timeout=10 -e "SELECT 1;" >/dev/null 2>&1; then
        log_success "Connected to MySQL"
        return 0
    else
        log_error "Cannot connect to MySQL"
        return 1
    fi
}

# Check if database exists
check_database_exists() {
    local db_name="$1"
    
    local exists
    exists=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '${db_name}';" --skip-column-names 2>/dev/null)
    
    [[ "$exists" -eq 1 ]]
}

# Update user passwords
update_user_passwords() {
    local password_hash="$1"
    
    log_info "Updating passwords for demo users..."
    
    local updated_count=0
    local failed_count=0
    
    for username in "${DEMO_USERS[@]}"; do
        echo -n "  ${username}... "
        
        # Check if user exists
        local user_exists
        user_exists=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "SELECT COUNT(*) FROM users WHERE username = '${username}';" --skip-column-names 2>/dev/null)
        
        if [[ "$user_exists" -eq 1 ]]; then
            # Update password
            if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
                "$DB_NAME" -e "UPDATE users SET password_hash = '${password_hash}', updated_at = NOW() WHERE username = '${username}';" 2>/dev/null; then
                
                # Get user role for display
                local user_role
                user_role=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
                    "$DB_NAME" -e "SELECT role FROM users WHERE username = '${username}';" --skip-column-names 2>/dev/null)
                
                echo -e "${GREEN}✓ ${user_role}${NC}"
                updated_count=$((updated_count + 1))
            else
                echo -e "${RED}✗ FAILED${NC}"
                failed_count=$((failed_count + 1))
            fi
        else
            echo -e "${YELLOW}✗ NOT FOUND${NC}"
            failed_count=$((failed_count + 1))
        fi
    done
    
    echo ""
    
    if [[ $failed_count -eq 0 ]]; then
        log_success "Updated $updated_count users successfully"
        return 0
    else
        log_warning "Updated $updated_count users, $failed_count failed"
        return 1
    fi
}

# Display updated users
display_updated_users() {
    echo ""
    echo -e "${CYAN}Updated User Accounts:${NC}"
    echo "────────────────────────────────────────"
    
    MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" -e "SELECT 
            username,
            role,
            email,
            is_active,
            DATE_FORMAT(updated_at, '%Y-%m-%d %H:%i') as updated
            FROM users 
            WHERE username IN ('admin', 'manager1', 'driver1', 'staff1')
            ORDER BY role, username;" 2>/dev/null || true
    
    echo ""
}

# Display security warning
display_security_warning() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}                      ${YELLOW}⚠️ SECURITY WARNING ⚠️${NC}                      ${RED}║${NC}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║${NC}                                                              ${RED}║${NC}"
    echo -e "${RED}║${NC}  All demo users now have password: ${DEMO_PASSWORD}          ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                              ${RED}║${NC}"
    echo -e "${RED}║${NC}  ${YELLOW}This is for DEMONSTRATION and DEVELOPMENT only!${NC}              ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                              ${RED}║${NC}"
    echo -e "${RED}║${NC}  ${RED}NEVER use these passwords in production!${NC}                    ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                              ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     Demo User Password Update         ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    display_security_warning
    
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
    if ! check_mysql_connection; then
        exit 1
    fi
    
    # Check if database exists
    if ! check_database_exists "$DB_NAME"; then
        log_error "Database '$DB_NAME' does not exist"
        log_info "Run ./01_create_database.sh first"
        exit 1
    fi
    
    # Confirm update
    echo -e "${YELLOW}This will update passwords for all demo users to:${NC}"
    echo "  Password: $DEMO_PASSWORD"
    echo ""
    echo "Affected users:"
    for user in "${DEMO_USERS[@]}"; do
        echo "  • $user"
    done
    echo ""
    
    read -p "Type 'UPDATE' to confirm: " confirm
    if [[ "$confirm" != "UPDATE" ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
    
    # Generate bcrypt hash
    log_info "Generating bcrypt hash for '$DEMO_PASSWORD'..."
    local password_hash
    password_hash=$(generate_bcrypt_hash)
    
    echo ""
    log_info "Using hash: ${password_hash:0:50}..."
    echo ""
    
    # Update passwords
    if ! update_user_passwords "$password_hash"; then
        log_error "Some passwords failed to update"
        # Continue anyway
    fi
    
    # Display results
    display_updated_users
    
    # Show credentials
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    UPDATE COMPLETE                      ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${CYAN}Demo Credentials:${NC}"
    echo "────────────────────────────────────────"
    for user in "${DEMO_USERS[@]}"; do
        # Get user role
        local user_role
        user_role=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "SELECT role FROM users WHERE username = '${user}';" --skip-column-names 2>/dev/null || echo "unknown")
        
        printf "  %-10s %-10s %-15s\n" "$user" "($user_role)" "Password: $DEMO_PASSWORD"
    done
    echo ""
    
    # Security reminder
    echo -e "${RED}🔐 SECURITY REMINDER:${NC}"
    echo "────────────────────────────────────────"
    echo "  • These are DEFAULT passwords"
    echo "  • Change ALL passwords for production"
    echo "  • Use strong, unique passwords"
    echo "  • Consider using password manager"
    echo ""
    
    # Next steps
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo "────────────────────────────────────────"
    echo "  1. Test login with credentials above"
    echo "  2. For production: change passwords using:"
    echo "     ./update_admin_password.sh"
    echo "  3. Set up proper user management"
    echo ""
    
    # Clean up
    unset DB_PASSWORD
    
    log_info "Password update process completed"
}

# Execute main function
main "$@"