#!/bin/bash
# Enhanced authentication test script
# Version: 2.0

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BACKEND_URL="http://localhost:3000"
FRONTEND_URL="http://localhost:8080"
API_TIMEOUT=5
TEST_USERS=("admin" "manager1" "driver1" "staff1")
TEST_PASSWORD="admin123"

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

# Check if command exists
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_warning "$cmd is not installed. Some tests may be limited."
        return 1
    fi
    return 0
}

# Test backend health
test_backend_health() {
    echo -n "Testing backend health ($BACKEND_URL)... "
    
    if curl -s --max-time "$API_TIMEOUT" "$BACKEND_URL/api/auth/health" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ ONLINE${NC}"
        
        # Try to get detailed response
        local response
        response=$(curl -s --max-time "$API_TIMEOUT" "$BACKEND_URL/api/auth/health" 2>/dev/null || true)
        
        if [[ -n "$response" ]]; then
            if check_command jq; then
                local status
                status=$(echo "$response" | jq -r '.status // .message // "unknown"' 2>/dev/null || echo "unknown")
                echo "  Status: $status"
            else
                echo "  Response: ${response:0:100}..."
            fi
        fi
        
        return 0
    else
        echo -e "${RED}✗ OFFLINE${NC}"
        return 1
    fi
}

# Test database connection
test_database_connection() {
    echo -n "Testing database connection... "
    
    if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        --connect-timeout=5 -e "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ CONNECTED${NC}"
        
        # Get database info
        local db_info
        db_info=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
            -e "SELECT 
                DATABASE() as db,
                USER() as user,
                VERSION() as version;" 2>/dev/null || true)
        
        if [[ -n "$db_info" ]]; then
            echo "  Database info retrieved"
        fi
        
        return 0
    else
        echo -e "${RED}✗ DISCONNECTED${NC}"
        return 1
    fi
}

# Test user authentication
test_user_login() {
    local username="$1"
    local password="$2"
    
    echo -n "  Testing $username... "
    
    local response
    response=$(curl -s --max-time "$API_TIMEOUT" \
        -X POST "$BACKEND_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$username\",\"password\":\"$password\"}" 2>/dev/null || echo "{}")
    
    if [[ -z "$response" ]] || [[ "$response" == "{}" ]]; then
        echo -e "${RED}✗ NO RESPONSE${NC}"
        return 1
    fi
    
    if check_command jq; then
        local success
        success=$(echo "$response" | jq -r '.success // false' 2>/dev/null || echo "false")
        local message
        message=$(echo "$response" | jq -r '.message // ""' 2>/dev/null || echo "")
        
        if [[ "$success" == "true" ]]; then
            local user_role
            user_role=$(echo "$response" | jq -r '.user.role // ""' 2>/dev/null || echo "")
            echo -e "${GREEN}✓ SUCCESS (Role: $user_role)${NC}"
            return 0
        else
            echo -e "${RED}✗ FAILED${NC}"
            if [[ -n "$message" ]]; then
                echo "    Error: $message"
            fi
            return 1
        fi
    else
        # Simple check without jq
        if echo "$response" | grep -q "success.*true"; then
            echo -e "${GREEN}✓ SUCCESS${NC}"
            return 0
        else
            echo -e "${RED}✗ FAILED${NC}"
            return 1
        fi
    fi
}

# Test wrong credentials
test_wrong_credentials() {
    echo -n "Testing wrong credentials... "
    
    local response
    response=$(curl -s --max-time "$API_TIMEOUT" \
        -X POST "$BACKEND_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"username":"admin","password":"wrongpassword"}' 2>/dev/null || echo "{}")
    
    if check_command jq; then
        local success
        success=$(echo "$response" | jq -r '.success // false' 2>/dev/null || echo "false")
        
        if [[ "$success" == "false" ]]; then
            echo -e "${GREEN}✓ CORRECTLY REJECTED${NC}"
            return 0
        else
            echo -e "${RED}✗ WRONGLY ACCEPTED${NC}"
            return 1
        fi
    else
        if echo "$response" | grep -q "Invalid\|incorrect\|failed"; then
            echo -e "${GREEN}✓ CORRECTLY REJECTED${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ UNKNOWN${NC}"
            return 0
        fi
    fi
}

# Test database users
test_database_users() {
    echo "Database Users:"
    echo "────────────────────────────────────────"
    
    local users
    users=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        "$DB_NAME" -e "SELECT 
            username,
            role,
            is_active,
            DATE_FORMAT(last_login, '%Y-%m-%d %H:%i') as last_login
            FROM users 
            ORDER BY role, username;" 2>/dev/null || true)
    
    if [[ -n "$users" ]]; then
        echo "$users" | while IFS=$'\t' read -r username role active last_login; do
            local status_color="${GREEN}"
            local status_symbol="✓"
            
            if [[ "$active" -eq 0 ]]; then
                status_color="${RED}"
                status_symbol="✗"
            fi
            
            printf "  %-15s %-10s ${status_color}%-6s${NC} %s\n" \
                "$username" "($role)" "$status_symbol" "${last_login:-Never}"
        done
    else
        echo "  Could not retrieve users"
    fi
}

# Test frontend accessibility
test_frontend() {
    echo -n "Testing frontend ($FRONTEND_URL)... "
    
    if curl -s --max-time "$API_TIMEOUT" "$FRONTEND_URL" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ ACCESSIBLE${NC}"
        return 0
    else
        echo -e "${RED}✗ INACCESSIBLE${NC}"
        return 1
    fi
}

# Run comprehensive authentication tests
run_auth_tests() {
    echo ""
    echo -e "${CYAN}Authentication Test Results:${NC}"
    echo "────────────────────────────────────────"
    
    local backend_ok=false
    local database_ok=false
    local frontend_ok=false
    local auth_tests_passed=0
    local auth_tests_total=0
    
    # Test backend
    if test_backend_health; then
        backend_ok=true
    fi
    
    # Test database
    if test_database_connection; then
        database_ok=true
    fi
    
    # Test frontend
    if test_frontend; then
        frontend_ok=true
    fi
    
    echo ""
    
    # Only run authentication tests if backend is available
    if [[ "$backend_ok" == true ]]; then
        echo "User Authentication Tests:"
        echo "────────────────────────────────────────"
        
        # Test correct credentials
        for user in "${TEST_USERS[@]}"; do
            auth_tests_total=$((auth_tests_total + 1))
            if test_user_login "$user" "$TEST_PASSWORD"; then
                auth_tests_passed=$((auth_tests_passed + 1))
            fi
        done
        
        # Test wrong credentials
        auth_tests_total=$((auth_tests_total + 1))
        if test_wrong_credentials; then
            auth_tests_passed=$((auth_tests_passed + 1))
        fi
        
        echo ""
    fi
    
    # Show database users
    if [[ "$database_ok" == true ]]; then
        test_database_users
        echo ""
    fi
    
    # Generate report
    generate_auth_report "$backend_ok" "$database_ok" "$frontend_ok" "$auth_tests_passed" "$auth_tests_total"
}

# Generate authentication report
generate_auth_report() {
    local backend_ok="$1"
    local database_ok="$2"
    local frontend_ok="$3"
    local auth_passed="$4"
    local auth_total="$5"
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}               AUTHENTICATION TEST REPORT                ${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Component status
    echo -e "${CYAN}Component Status:${NC}"
    echo "────────────────────────────────────────"
    
    local components=("Backend API" "Database" "Frontend")
    local component_status=("$backend_ok" "$database_ok" "$frontend_ok")
    
    for i in "${!components[@]}"; do
        local component="${components[$i]}"
        local status="${component_status[$i]}"
        
        if [[ "$status" == true ]]; then
            printf "  %-15s ${GREEN}✓ OPERATIONAL${NC}\n" "$component"
        else
            printf "  %-15s ${RED}✗ OFFLINE${NC}\n" "$component"
        fi
    done
    
    echo ""
    
    # Authentication test results
    if [[ $auth_total -gt 0 ]]; then
        echo -e "${CYAN}Authentication Tests:${NC}"
        echo "────────────────────────────────────────"
        echo "  Passed: $auth_passed/$auth_total"
        
        local auth_score=0
        if [[ $auth_total -gt 0 ]]; then
            auth_score=$((auth_passed * 100 / auth_total))
        fi
        
        echo "  Score:  $auth_score%"
        echo ""
        
        # Authentication status
        echo -e "${CYAN}Authentication Status:${NC}"
        echo "────────────────────────────────────────"
        
        if [[ $auth_passed -eq $auth_total ]]; then
            echo -e "  ${GREEN}✅ ALL TESTS PASSED${NC}"
            echo "  Authentication system is working correctly"
        elif [[ $auth_passed -eq 0 ]]; then
            echo -e "  ${RED}❌ ALL TESTS FAILED${NC}"
            echo "  Authentication system is not working"
        else
            echo -e "  ${YELLOW}⚠️  PARTIAL SUCCESS${NC}"
            echo "  Some authentication tests failed"
        fi
        echo ""
    fi
    
    # Issues and recommendations
    echo -e "${CYAN}Issues & Recommendations:${NC}"
    echo "────────────────────────────────────────"
    
    local has_issues=false
    
    if [[ "$backend_ok" != true ]]; then
        echo -e "  ${RED}• Backend API is not responding${NC}"
        echo "    Check if backend server is running:"
        echo "      cd ../backend && npm start"
        has_issues=true
    fi
    
    if [[ "$database_ok" != true ]]; then
        echo -e "  ${RED}• Database connection failed${NC}"
        echo "    Check MySQL service and credentials:"
        echo "      sudo systemctl status mysql"
        echo "      Check ../backend/.env file"
        has_issues=true
    fi
    
    if [[ $auth_total -eq 0 ]] && [[ "$backend_ok" == true ]]; then
        echo -e "  ${YELLOW}• No authentication tests were run${NC}"
        echo "    Check if authentication endpoint is available"
        has_issues=true
    fi
    
    if [[ $auth_passed -lt $auth_total ]] && [[ $auth_total -gt 0 ]]; then
        echo -e "  ${YELLOW}• Some authentication tests failed${NC}"
        echo "    Check user credentials in database:"
        echo "      ./update_admin_password.sh"
        has_issues=true
    fi
    
    if [[ "$has_issues" != true ]]; then
        echo -e "  ${GREEN}• No major issues detected${NC}"
    fi
    
    echo ""
    
    # Quick access information
    echo -e "${CYAN}Quick Access:${NC}"
    echo "────────────────────────────────────────"
    echo "  Frontend Login:  $FRONTEND_URL/login.html"
    echo "  Backend API:     $BACKEND_URL/api"
    echo "  Database:        $DB_NAME@$DB_HOST:$DB_PORT"
    echo ""
    
    # Test credentials
    if [[ "$database_ok" == true ]]; then
        echo -e "${CYAN}Test Credentials:${NC}"
        echo "────────────────────────────────────────"
        for user in "${TEST_USERS[@]}"; do
            echo "  $user / $TEST_PASSWORD"
        done
        echo ""
        echo -e "${YELLOW}⚠️  These are default development credentials${NC}"
        echo "  Change them for production use"
        echo ""
    fi
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     Authentication System Test         ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Check for required commands
    check_command curl
    check_command mysql
    
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
    
    echo "Test Configuration:"
    echo "  Backend URL:  $BACKEND_URL"
    echo "  Frontend URL: $FRONTEND_URL"
    echo "  Database:     $DB_NAME@$DB_HOST:$DB_PORT"
    echo ""
    
    # Run tests
    run_auth_tests
    
    # Clean up
    unset DB_PASSWORD
    
    log_info "Authentication test completed"
}

# Execute main function
main "$@"