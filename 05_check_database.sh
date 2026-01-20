#!/bin/bash
# Enhanced database health check script
# Version: 2.0

set -euo pipefail

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
WARNING_THRESHOLD=80  # Percentage for warnings
CRITICAL_THRESHOLD=90 # Percentage for critical alerts

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

# Execute MySQL query safely
mysql_query() {
    local query="$1"
    
    MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        --silent \
        --skip-column-names \
        "$DB_NAME" \
        -e "$query" 2>/dev/null || echo "ERROR"
}

# Check database connection
check_connection() {
    echo -n "Database Connection............ "
    if MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        --connect-timeout=5 -e "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        return 1
    fi
}

# Check if database exists
check_database_exists() {
    echo -n "Database Existence............. "
    
    local exists
    exists=$(MYSQL_PWD="${DB_PASSWORD}" mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = '${DB_NAME}';" --skip-column-names 2>/dev/null)
    
    if [[ "$exists" -eq 1 ]]; then
        echo -e "${GREEN}✓ FOUND${NC}"
        return 0
    else
        echo -e "${RED}✗ NOT FOUND${NC}"
        return 1
    fi
}

# Check table count
check_tables() {
    echo -n "Table Count.................... "
    
    local table_count
    table_count=$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${DB_NAME}';")
    
    if [[ "$table_count" != "ERROR" ]] && [[ $table_count -gt 0 ]]; then
        echo -e "${GREEN}✓ $table_count tables${NC}"
        return 0
    else
        echo -e "${RED}✗ No tables found${NC}"
        return 1
    fi
}

# Check data integrity
check_data_integrity() {
    echo -n "Data Integrity................. "
    
    # Check for orphaned records
    local orphans=0
    local checks=0
    
    # Check shipments without customers
    local orphaned_shipments
    orphaned_shipments=$(mysql_query "SELECT COUNT(*) FROM shipments s LEFT JOIN customers c ON s.customer_id = c.id WHERE c.id IS NULL;")
    if [[ "$orphaned_shipments" != "ERROR" ]] && [[ $orphaned_shipments -gt 0 ]]; then
        orphans=$((orphans + orphaned_shipments))
    fi
    checks=$((checks + 1))
    
    # Check status history without shipments
    local orphaned_history
    orphaned_history=$(mysql_query "SELECT COUNT(*) FROM status_history sh LEFT JOIN shipments s ON sh.shipment_id = s.id WHERE s.id IS NULL;")
    if [[ "$orphaned_history" != "ERROR" ]] && [[ $orphaned_history -gt 0 ]]; then
        orphans=$((orphans + orphaned_history))
    fi
    checks=$((checks + 1))
    
    if [[ $orphans -eq 0 ]]; then
        echo -e "${GREEN}✓ OK ($checks checks passed)${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ $orphans orphaned records found${NC}"
        return 1
    fi
}

# Check foreign key constraints
check_foreign_keys() {
    echo -n "Foreign Key Constraints........ "
    
    # Try to check foreign key constraints
    local fk_check
    fk_check=$(mysql_query "SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE constraint_type = 'FOREIGN KEY' AND table_schema = '${DB_NAME}';")
    
    if [[ "$fk_check" != "ERROR" ]]; then
        echo -e "${GREEN}✓ $fk_check constraints${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ Cannot check constraints${NC}"
        return 1
    fi
}

# Check table sizes and growth
check_table_sizes() {
    echo "Table Sizes:"
    echo "  ┌──────────────────────────────┬────────────┬────────────┐"
    echo "  │ Table Name                   │ Rows       │ Size (MB)  │"
    echo "  ├──────────────────────────────┼────────────┼────────────┤"
    
    local total_rows=0
    local total_size=0
    
    # Get table sizes
    while IFS=$'\t' read -r table_name rows size_mb; do
        printf "  │ %-28s │ %10s │ %10s │\n" "$table_name" "$rows" "$size_mb"
        total_rows=$((total_rows + rows))
        total_size=$((total_size + size_mb))
    done < <(mysql_query "SELECT 
        table_name,
        table_rows,
        ROUND((data_length + index_length) / 1024 / 1024, 2) as size_mb
        FROM information_schema.tables 
        WHERE table_schema = '${DB_NAME}'
        ORDER BY (data_length + index_length) DESC
        LIMIT 10;")
    
    echo "  ├──────────────────────────────┼────────────┼────────────┤"
    printf "  │ %-28s │ %10s │ %10s │\n" "TOTAL (top 10)" "$total_rows" "$total_size"
    echo "  └──────────────────────────────┴────────────┴────────────┘"
}

# Check performance metrics
check_performance() {
    echo "Performance Metrics:"
    
    # Connection count
    local connections
    connections=$(mysql_query "SHOW STATUS LIKE 'Threads_connected';" | awk '{print $2}')
    if [[ "$connections" != "ERROR" ]]; then
        echo -n "  Active Connections........... "
        if [[ $connections -gt 50 ]]; then
            echo -e "${YELLOW}$connections (High)${NC}"
        else
            echo -e "${GREEN}$connections${NC}"
        fi
    fi
    
    # Slow queries
    local slow_queries
    slow_queries=$(mysql_query "SHOW STATUS LIKE 'Slow_queries';" | awk '{print $2}')
    if [[ "$slow_queries" != "ERROR" ]]; then
        echo -n "  Slow Queries................. "
        if [[ $slow_queries -gt 10 ]]; then
            echo -e "${YELLOW}$slow_queries${NC}"
        else
            echo -e "${GREEN}$slow_queries${NC}"
        fi
    fi
    
    # Query cache hit rate
    local qcache_hits qcache_inserts hit_rate
    qcache_hits=$(mysql_query "SHOW STATUS LIKE 'Qcache_hits';" | awk '{print $2}')
    qcache_inserts=$(mysql_query "SHOW STATUS LIKE 'Qcache_inserts';" | awk '{print $2}')
    
    if [[ "$qcache_hits" != "ERROR" ]] && [[ "$qcache_inserts" != "ERROR" ]] && [[ $qcache_hits -gt 0 ]]; then
        if [[ $((qcache_hits + qcache_inserts)) -gt 0 ]]; then
            hit_rate=$((qcache_hits * 100 / (qcache_hits + qcache_inserts)))
            echo -n "  Query Cache Hit Rate........ "
            if [[ $hit_rate -lt 50 ]]; then
                echo -e "${YELLOW}$hit_rate%${NC}"
            else
                echo -e "${GREEN}$hit_rate%${NC}"
            fi
        fi
    fi
}

# Check replication status (if applicable)
check_replication() {
    echo -n "Replication Status............. "
    
    local slave_status
    slave_status=$(mysql_query "SHOW SLAVE STATUS\G" 2>/dev/null | grep -c "Slave_IO_Running: Yes")
    
    if [[ $slave_status -gt 0 ]]; then
        echo -e "${GREEN}✓ Replication Active${NC}"
    else
        echo -e "${CYAN}○ Not Configured${NC}"
    fi
}

# Check backup status
check_backups() {
    echo -n "Recent Backups................. "
    
    local backup_dir="../backups"
    local recent_backups
    
    if [[ -d "$backup_dir" ]]; then
        recent_backups=$(find "$backup_dir" -name "*.sql.gz" -mtime -1 | wc -l)
        
        if [[ $recent_backups -gt 0 ]]; then
            echo -e "${GREEN}✓ $recent_backups in last 24h${NC}"
        else
            echo -e "${YELLOW}⚠ No recent backups${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Backup directory not found${NC}"
    fi
}

# Check user accounts
check_users() {
    echo "User Accounts:"
    
    local users
    users=$(mysql_query "SELECT 
        username,
        role,
        is_active,
        DATE_FORMAT(last_login, '%Y-%m-%d') as last_login
        FROM users
        ORDER BY role, username;")
    
    if [[ "$users" != "ERROR" ]] && [[ -n "$users" ]]; then
        echo "  ┌──────────────────────┬────────────┬────────┬────────────┐"
        echo "  │ Username             │ Role       │ Active │ Last Login │"
        echo "  ├──────────────────────┼────────────┼────────┼────────────┤"
        
        while IFS=$'\t' read -r username role active last_login; do
            local active_status="✓"
            local active_color="${GREEN}"
            if [[ "$active" -eq 0 ]]; then
                active_status="✗"
                active_color="${RED}"
            fi
            
            printf "  │ %-20s │ %-10s │ ${active_color}%-6s${NC} │ %-10s │\n" \
                "$username" "$role" "$active_status" "${last_login:-Never}"
        done <<< "$users"
        
        echo "  └──────────────────────┴────────────┴────────┴────────────┘"
    fi
}

# Check critical data counts
check_data_counts() {
    echo "Critical Data Counts:"
    
    # Define critical tables to check
    declare -A critical_tables=(
        ["users"]="SELECT COUNT(*) FROM users WHERE is_active = 1;"
        ["customers"]="SELECT COUNT(*) FROM customers WHERE is_active = 1;"
        ["active_shipments"]="SELECT COUNT(*) FROM shipments WHERE status NOT IN ('delivered', 'cancelled');"
        ["pending_invoices"]="SELECT COUNT(*) FROM invoices WHERE status IN ('sent', 'overdue');"
        ["available_vehicles"]="SELECT COUNT(*) FROM vehicles WHERE status = 'available';"
    )
    
    for table in "${!critical_tables[@]}"; do
        local query="${critical_tables[$table]}"
        local count
        count=$(mysql_query "$query")
        
        if [[ "$count" != "ERROR" ]]; then
            printf "  %-25s " "$table:"
            echo -e "${CYAN}$count${NC}"
        fi
    done
}

# Check system health
check_system_health() {
    echo "System Health:"
    
    # Database size
    local db_size
    db_size=$(mysql_query "SELECT 
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as size_mb
        FROM information_schema.tables 
        WHERE table_schema = '${DB_NAME}';")
    
    if [[ "$db_size" != "ERROR" ]]; then
        echo -n "  Database Size............... "
        if [[ $(echo "$db_size > 1000" | bc -l 2>/dev/null) -eq 1 ]]; then
            echo -e "${YELLOW}$db_size MB${NC}"
        else
            echo -e "${GREEN}$db_size MB${NC}"
        fi
    fi
    
    # Uptime
    local uptime
    uptime=$(mysql_query "SHOW STATUS LIKE 'Uptime';" | awk '{print $2}')
    if [[ "$uptime" != "ERROR" ]] && [[ -n "$uptime" ]]; then
        local uptime_days=$((uptime / 86400))
        local uptime_hours=$(( (uptime % 86400) / 3600 ))
        
        echo -n "  MySQL Uptime............... "
        echo -e "${GREEN}${uptime_days}d ${uptime_hours}h${NC}"
    fi
    
    # Version
    local version
    version=$(mysql_query "SELECT VERSION();")
    if [[ "$version" != "ERROR" ]]; then
        echo -n "  MySQL Version.............. "
        echo -e "${CYAN}$version${NC}"
    fi
}

# Check for long-running queries
check_long_running_queries() {
    echo -n "Long-Running Queries.......... "
    
    local long_queries
    long_queries=$(mysql_query "SELECT COUNT(*) FROM information_schema.processlist WHERE TIME > 60;")
    
    if [[ "$long_queries" != "ERROR" ]]; then
        if [[ $long_queries -gt 0 ]]; then
            echo -e "${YELLOW}$long_queries found${NC}"
            return 1
        else
            echo -e "${GREEN}None${NC}"
            return 0
        fi
    else
        echo -e "${CYAN}Cannot check${NC}"
        return 0
    fi
}

# Generate health report
generate_report() {
    local checks_passed=0
    local checks_total=0
    local warnings=0
    local errors=0
    
    # Run checks and count results
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     Database Health Check Report       ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Basic checks
    check_connection && ((checks_passed++)) || ((errors++))
    ((checks_total++))
    
    check_database_exists && ((checks_passed++)) || ((errors++))
    ((checks_total++))
    
    check_tables && ((checks_passed++)) || ((errors++))
    ((checks_total++))
    
    check_data_integrity && ((checks_passed++)) || ((warnings++))
    ((checks_total++))
    
    check_foreign_keys && ((checks_passed++)) || ((warnings++))
    ((checks_total++))
    
    check_long_running_queries && ((checks_passed++)) || ((warnings++))
    ((checks_total++))
    
    check_backups && ((checks_passed++)) || ((warnings++))
    ((checks_total++))
    
    echo ""
    
    # Detailed information
    check_table_sizes
    echo ""
    
    check_performance
    echo ""
    
    check_system_health
    echo ""
    
    check_data_counts
    echo ""
    
    check_users
    echo ""
    
    # Summary
    local health_score=$((checks_passed * 100 / checks_total))
    
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    HEALTH SUMMARY                       ${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Health status
    if [[ $errors -gt 0 ]]; then
        echo -e "  Status:    ${RED}❌ UNHEALTHY${NC}"
    elif [[ $warnings -gt 0 ]]; then
        echo -e "  Status:    ${YELLOW}⚠️  WARNING${NC}"
    else
        echo -e "  Status:    ${GREEN}✅ HEALTHY${NC}"
    fi
    
    # Metrics
    echo "  Checks:    $checks_passed/$checks_total passed"
    echo "  Score:     $health_score%"
    echo "  Warnings:  $warnings"
    echo "  Errors:    $errors"
    echo ""
    
    # Recommendations
    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}❌ IMMEDIATE ACTION REQUIRED:${NC}"
        echo "  • Fix connection/database existence issues"
        echo "  • Check MySQL service status"
        echo "  • Verify credentials"
        echo ""
    fi
    
    if [[ $warnings -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  RECOMMENDATIONS:${NC}"
        echo "  • Review orphaned records"
        echo "  • Check backup schedule"
        echo "  • Monitor performance metrics"
        echo ""
    fi
    
    # Next steps
    echo -e "${BLUE}🚀 NEXT STEPS:${NC}"
    echo "────────────────────────────────────────"
    echo "  1. Regular backups (daily)"
    echo "  2. Monitor slow queries"
    echo "  3. Review user activity"
    echo "  4. Update indexes if needed"
    echo ""
    
    echo -e "${BLUE}📊 MONITORING SUGGESTIONS:${NC}"
    echo "────────────────────────────────────────"
    echo "  • Database size growth"
    echo "  • Active connections"
    echo "  • Query performance"
    echo "  • Backup success rate"
    echo ""
    
    return $errors
}

# Main execution
main() {
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
    
    # Hide password
    local password_display=""
    if [[ -n "$DB_PASSWORD" ]]; then
        password_display="********"
    fi
    
    echo ""
    echo "Database Configuration:"
    echo "  Host:     $DB_HOST:$DB_PORT"
    echo "  Database: $DB_NAME"
    echo "  User:     $DB_USER"
    echo "  Password: $password_display"
    echo ""
    
    # Generate report
    if ! generate_report; then
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}  Health check failed with errors!      ${NC}"
        echo -e "${RED}========================================${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Health check completed successfully!  ${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # Clean up
    unset DB_PASSWORD
}

# Execute main function
main "$@"