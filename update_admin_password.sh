#!/bin/bash
# Secure admin password update script
# Version: 2.0

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default password (for development only)
DEFAULT_PASSWORD="admin123"
SECURE_PASSWORD_LENGTH=16

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

# Function to generate secure password
generate_secure_password() {
    local length="${1:-$SECURE_PASSWORD_LENGTH}"
    
    # Try different methods for password generation
    if command -v openssl >/dev/null 2>&1; then
        # Use openssl
        openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' | head -c "$length"
    elif command -v pwgen >/dev/null 2>&1; then
        # Use pwgen
        pwgen -s "$length" 1
    elif [[ -f /dev/urandom ]]; then
        # Use /dev/urandom
        tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length"
    else
        # Fallback to simple random
        date +%s | sha256sum | base64 | head -c "$length"
    fi
    echo ""  # Add newline
}

# Function to generate bcrypt hash
generate_bcrypt_hash() {
    local password="$1"
    
    # Try multiple methods to generate bcrypt hash
    local hash=""
    
    # Method 1: Node.js (preferred)
    if command -v node >/dev/null 2>&1; then
        log_info "Using Node.js to generate bcrypt hash..."
        
        # Check if bcrypt is available
        if node -e "require('bcrypt')" 2>/dev/null; then
            hash=$(node -e "
                const bcrypt = require('bcrypt');
                const saltRounds = 10;
                const salt = bcrypt.genSaltSync(saltRounds);
                const hash = bcrypt.hashSync('$password', salt);
                console.log(hash);
            " 2>/dev/null)
        else
            log_warning "bcrypt not installed in Node.js"
        fi
    fi
    
    # Method 2: Python
    if [[ -z "$hash" ]] && command -v python3 >/dev/null 2>&1; then
        log_info "Using Python to generate bcrypt hash..."
        
        hash=$(python3 -c "
import bcrypt
import sys
password = '$password'.encode('utf-8')
salt = bcrypt.gensalt(rounds=10)
hashed = bcrypt.hashpw(password, salt)
print(hashed.decode('utf-8'))
" 2>/dev/null)
    fi
    
    # Method 3: PHP
    if [[ -z "$hash" ]] && command -v php >/dev/null 2>&1; then
        log_info "Using PHP to generate bcrypt hash..."
        
        hash=$(php -r "
echo password_hash('$password', PASSWORD_BCRYPT, ['cost' => 10]);
" 2>/dev/null)
    fi
    
    # Method 4: Use pre-generated hash for default password
    if [[ -z "$hash" ]]; then
        log_warning "No bcrypt generator found. Using pre-generated hash."
        
        # Pre-generated bcrypt hash for 'admin123'
        if [[ "$password" == "$DEFAULT_PASSWORD" ]]; then
            hash='$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy'
        else
            log_error "Cannot generate hash for custom password without bcrypt"
            return 1
        fi
    fi
    
    echo "$hash"
}

# Function to check MySQL connection
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

# Function to check if database exists
check_database_exists() {
    local db_name="$1"
    
    local exists
    exists=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '${db_name}';" --skip-column-names 2>/dev/null)
    
    [[ "$exists" -eq 1 ]]
}

# Function to check if user exists
check_user_exists() {
    local username="$1"
    
    local exists
    exists=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" -e "SELECT COUNT(*) FROM users WHERE username = '${username}';" --skip-column-names 2>/dev/null)
    
    [[ "$exists" -eq 1 ]]
}

# Function to get user information
get_user_info() {
    local username="$1"
    
    MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" -e "SELECT 
            username,
            email,
            role,
            is_active,
            DATE_FORMAT(last_login, '%Y-%m-%d %H:%i') as last_login
            FROM users 
            WHERE username = '${username}';" 2>/dev/null
}

# Function to update password
update_password() {
    local username="$1"
    local password_hash="$2"
    local updated_by="${3:-1}"  # Default to admin user ID
    
    log_info "Updating password for user: $username"
    
    # Update password using stored procedure if available
    local procedure_exists
    procedure_exists=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" -e "SELECT COUNT(*) FROM information_schema.routines WHERE routine_name = 'change_user_password';" --skip-column-names 2>/dev/null)
    
    if [[ "$procedure_exists" -eq 1 ]]; then
        log_info "Using secure password change procedure..."
        
        if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "CALL change_user_password('${username}', '${password_hash}', ${updated_by});" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    else
        # Fallback to direct update
        log_info "Using direct update (fallback)..."
        
        if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "UPDATE users SET password_hash = '${password_hash}', updated_at = NOW() WHERE username = '${username}';" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi
}

# Function to verify password update
verify_password_update() {
    local username="$1"
    local expected_hash="$2"
    
    log_info "Verifying password update..."
    
    local current_hash
    current_hash=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" -e "SELECT password_hash FROM users WHERE username = '${username}';" --skip-column-names 2>/dev/null)
    
    if [[ "$current_hash" == "$expected_hash" ]]; then
        log_success "Password verification successful"
        return 0
    else
        log_error "Password verification failed"
        echo "  Expected: ${expected_hash:0:20}..."
        echo "  Actual:   ${current_hash:0:20}..."
        return 1
    fi
}

# Function to display password policy
display_password_policy() {
    echo ""
    echo -e "${CYAN}Password Policy Requirements:${NC}"
    echo "────────────────────────────────────────"
    echo "  • Minimum 12 characters"
    echo "  • At least one uppercase letter"
    echo "  • At least one lowercase letter"
    echo "  • At least one number"
    echo "  • At least one special character"
    echo "  • No common dictionary words"
    echo "  • Not based on personal information"
    echo ""
}

# Function to validate password strength
validate_password_strength() {
    local password="$1"
    local min_length=12
    
    # Check length
    if [[ ${#password} -lt $min_length ]]; then
        echo "Password must be at least $min_length characters"
        return 1
    fi
    
    # Check for uppercase
    if ! [[ "$password" =~ [A-Z] ]]; then
        echo "Password must contain at least one uppercase letter"
        return 1
    fi
    
    # Check for lowercase
    if ! [[ "$password" =~ [a-z] ]]; then
        echo "Password must contain at least one lowercase letter"
        return 1
    fi
    
    # Check for numbers
    if ! [[ "$password" =~ [0-9] ]]; then
        echo "Password must contain at least one number"
        return 1
    fi
    
    # Check for special characters
    if ! [[ "$password" =~ [!@#$%^&*()_+\-=\[\]{}|;:,.<>?] ]]; then
        echo "Password must contain at least one special character"
        return 1
    fi
    
    # Check for common passwords (simple check)
    local common_passwords=("password" "123456" "admin" "letmein" "welcome" "monkey" "dragon")
    for common in "${common_passwords[@]}"; do
        if [[ "$password" == *"$common"* ]]; then
            echo "Password contains common dictionary word: $common"
            return 1
        fi
    done
    
    return 0
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     Admin Password Update Utility      ${NC}"
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
    if ! check_mysql_connection; then
        exit 1
    fi
    
    # Check if database exists
    if ! check_database_exists "$DB_NAME"; then
        log_error "Database '$DB_NAME' does not exist"
        log_info "Run ./01_create_database.sh first"
        exit 1
    fi
    
    # Check if admin user exists
    if ! check_user_exists "admin"; then
        log_error "Admin user does not exist in database"
        
        # Show existing users
        log_info "Existing users:"
        MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            "$DB_NAME" -e "SELECT username, email, role FROM users;" 2>/dev/null || true
        
        exit 1
    fi
    
    # Show current admin info
    echo ""
    echo -e "${CYAN}Current Admin Information:${NC}"
    echo "────────────────────────────────────────"
    get_user_info "admin"
    echo ""
    
    # Password selection
    echo -e "${YELLOW}Password Options:${NC}"
    echo "────────────────────────────────────────"
    echo "  1) Use default development password: $DEFAULT_PASSWORD"
    echo "  2) Generate secure random password"
    echo "  3) Enter custom password"
    echo ""
    
    local password_choice
    read -p "Select option [1/2/3]: " password_choice
    
    local new_password=""
    
    case $password_choice in
        1)
            new_password="$DEFAULT_PASSWORD"
            log_warning "Using default development password"
            ;;
        2)
            log_info "Generating secure password..."
            new_password=$(generate_secure_password)
            echo ""
            echo -e "${GREEN}Generated Password:${NC} $new_password"
            echo ""
            
            # Ask if user wants to see the password
            read -p "Show password again? (yes/no): " show_again
            if [[ "$show_again" == "yes" ]]; then
                echo "Password: $new_password"
            fi
            ;;
        3)
            display_password_policy
            
            local password_valid=false
            local attempts=0
            local max_attempts=3
            
            while [[ $attempts -lt $max_attempts ]] && [[ "$password_valid" == false ]]; do
                attempts=$((attempts + 1))
                
                read -sp "Enter new password: " password1
                echo ""
                read -sp "Confirm new password: " password2
                echo ""
                
                if [[ "$password1" != "$password2" ]]; then
                    log_error "Passwords do not match"
                    continue
                fi
                
                if validate_password_strength "$password1"; then
                    new_password="$password1"
                    password_valid=true
                else
                    log_warning "Password does not meet strength requirements"
                    echo ""
                fi
            done
            
            if [[ "$password_valid" == false ]]; then
                log_error "Failed to set password after $max_attempts attempts"
                exit 1
            fi
            ;;
        *)
            log_error "Invalid selection"
            exit 1
            ;;
    esac
    
    # Security warning for default password
    if [[ "$new_password" == "$DEFAULT_PASSWORD" ]]; then
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}                      ${YELLOW}⚠️ SECURITY WARNING ⚠️${NC}                      ${RED}║${NC}"
        echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║${NC}                                                              ${RED}║${NC}"
        echo -e "${RED}║${NC}  You are using the default development password!            ${RED}║${NC}"
        echo -e "${RED}║${NC}                                                              ${RED}║${NC}"
        echo -e "${RED}║${NC}  ${YELLOW}This is INSECURE and should NEVER be used in production!${NC}    ${RED}║${NC}"
        echo -e "${RED}║${NC}                                                              ${RED}║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "Continue with insecure password? (yes/no): " insecure_confirm
        if [[ "$insecure_confirm" != "yes" ]]; then
            log_info "Operation cancelled"
            exit 0
        fi
    fi
    
    # Generate bcrypt hash
    log_info "Generating bcrypt hash..."
    local password_hash
    password_hash=$(generate_bcrypt_hash "$new_password")
    
    if [[ $? -ne 0 ]] || [[ -z "$password_hash" ]]; then
        log_error "Failed to generate password hash"
        exit 1
    fi
    
    echo ""
    log_info "Generated hash (first 50 chars): ${password_hash:0:50}..."
    echo ""
    
    # Update password
    if update_password "admin" "$password_hash"; then
        log_success "Password updated in database"
    else
        log_error "Failed to update password"
        exit 1
    fi
    
    # Verify update
    if verify_password_update "admin" "$password_hash"; then
        log_success "✅ Password update verified successfully!"
    else
        log_error "Password update verification failed"
        exit 1
    fi
    
    # Display results
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    UPDATE COMPLETE                      ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [[ "$password_choice" -eq 2 ]]; then
        echo -e "${CYAN}Generated Password:${NC}"
        echo "  $new_password"
        echo ""
        echo -e "${YELLOW}⚠️  Save this password in a secure location!${NC}"
        echo ""
    fi
    
    echo "You can now login with:"
    echo "  Username: admin"
    
    if [[ "$password_choice" -eq 2 ]]; then
        echo "  Password: [see above]"
    else
        echo "  Password: $new_password"
    fi
    
    echo ""
    echo -e "${BLUE}Test Login:${NC}"
    echo "────────────────────────────────────────"
    echo "  1. Go to: http://localhost:8080/login.html"
    echo "  2. Enter credentials above"
    echo "  3. You should be redirected to dashboard"
    echo ""
    
    # Security recommendations
    if [[ "$new_password" == "$DEFAULT_PASSWORD" ]]; then
        echo -e "${RED}SECURITY RECOMMENDATIONS:${NC}"
        echo "────────────────────────────────────────"
        echo "  • Change password immediately in production"
        echo "  • Use strong, unique password"
        echo "  • Enable two-factor authentication"
        echo "  • Regularly rotate passwords"
        echo ""
    else
        echo -e "${GREEN}SECURITY STATUS:${NC}"
        echo "────────────────────────────────────────"
        echo "  • Password strength: Good"
        echo "  • Hash algorithm: bcrypt"
        echo "  • Salt rounds: 10"
        echo ""
    fi
    
    # Clean up
    unset DB_PASSWORD
    unset new_password
    
    log_info "Password update completed successfully"
}

# Execute main function
main "$@"