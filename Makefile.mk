# ============================================
# Logistics Platform Database Management
# ============================================

.PHONY: help init reset backup restore check secure test clean config

# Default target
help:
	@echo ""
	@echo -e "\033[1;34m========================================\033[0m"
	@echo -e "\033[1;34m    Logistics Platform Database        \033[0m"
	@echo -e "\033[1;34m========================================\033[0m"
	@echo ""
	@echo -e "\033[1;33mDatabase Management Commands:\033[0m"
	@echo "  make init     - Create and initialize database"
	@echo "  make reset    - Reset database (CAUTION: deletes all data)"
	@echo "  make backup   - Create database backup"
	@echo "  make restore  - Restore from backup"
	@echo "  make check    - Check database health"
	@echo "  make secure   - Run security hardening"
	@echo "  make test     - Test authentication system"
	@echo "  make clean    - Clean up temporary files"
	@echo "  make config   - Show current configuration"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo -e "\033[1;33mUser Management Commands:\033[0m"
	@echo "  make update-admin   - Update admin password"
	@echo "  make update-all     - Update all demo user passwords"
	@echo ""
	@echo -e "\033[1;33mShortcuts:\033[0m"
	@echo "  make db-init   - Alias for init"
	@echo "  make db-backup - Alias for backup"
	@echo "  make db-check  - Alias for check"
	@echo ""
	@echo -e "\033[1;33mExamples:\033[0m"
	@echo "  First time setup:"
	@echo "    make init"
	@echo "    make update-admin"
	@echo ""
	@echo "  Regular maintenance:"
	@echo "    make backup"
	@echo "    make check"
	@echo ""
	@echo -e "\033[1;31m⚠️  WARNING:\033[0m"
	@echo "  Some commands will delete data. Always backup first!"
	@echo ""

# Database initialization
init: db-init

db-init:
	@echo -e "\033[1;34m[Initializing Database]\033[0m"
	@chmod +x 01_create_database.sh
	@./01_create_database.sh

# Database reset (DANGEROUS!)
reset:
	@echo -e "\033[1;31m[Resetting Database]\033[0m"
	@echo -e "\033[1;31m⚠️  WARNING: This will delete ALL data!\033[0m"
	@read -p "Type 'confirm' to proceed: " confirm; \
	if [ "$$confirm" = "confirm" ]; then \
		chmod +x 02_reset_database.sh; \
		./02_reset_database.sh; \
	else \
		echo -e "\033[1;33mOperation cancelled\033[0m"; \
	fi

# Database backup
backup: db-backup

db-backup:
	@echo -e "\033[1;34m[Creating Database Backup]\033[0m"
	@chmod +x 03_backup_database.sh
	@./03_backup_database.sh

# Database restore
restore:
	@echo -e "\033[1;34m[Restoring Database]\033[0m"
	@chmod +x 04_restore_database.sh
	@./04_restore_database.sh

# Database health check
check: db-check

db-check:
	@echo -e "\033[1;34m[Checking Database Health]\033[0m"
	@chmod +x 05_check_database.sh
	@./05_check_database.sh

# Security hardening
secure:
	@echo -e "\033[1;34m[Running Security Hardening]\033[0m"
	@echo "Security hardening includes:"
	@echo "  • Password policy enforcement"
	@echo "  • User permission review"
	@echo "  • Audit logging configuration"
	@echo ""
	@read -p "Continue? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "Running security checks..."; \
		./05_check_database.sh | grep -A5 "SECURITY"; \
	else \
		echo -e "\033[1;33mOperation cancelled\033[0m"; \
	fi

# Authentication test
test:
	@echo -e "\033[1;34m[Testing Authentication System]\033[0m"
	@chmod +x test_auth.sh
	@./test_auth.sh

# Update admin password
update-admin:
	@echo -e "\033[1;34m[Updating Admin Password]\033[0m"
	@chmod +x update_admin_password.sh
	@./update_admin_password.sh

# Update all demo passwords
update-all:
	@echo -e "\033[1;34m[Updating All Demo Passwords]\033[0m"
	@echo -e "\033[1;33m⚠️  This sets all demo users to password: admin123\033[0m"
	@read -p "Continue? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		chmod +x update_all_passwords.sh; \
		./update_all_passwords.sh; \
	else \
		echo -e "\033[1;33mOperation cancelled\033[0m"; \
	fi

# Clean temporary files
clean:
	@echo -e "\033[1;34m[Cleaning Temporary Files]\033[0m"
	@rm -f ../backups/*.tmp 2>/dev/null || true
	@rm -f /tmp/temp_backup.sql 2>/dev/null || true
	@rm -f /tmp/generate_bcrypt.js 2>/dev/null || true
	@find ../logs -name "*.log" -mtime +30 -delete 2>/dev/null || true
	@echo -e "\033[1;32m✅ Cleanup completed\033[0m"

# Show configuration
config:
	@echo -e "\033[1;34m[Current Configuration]\033[0m"
	@echo ""
	@if [ -f "../backend/.env" ]; then \
		echo -e "\033[1;33mEnvironment File:\033[0m"; \
		echo "  Location: ../backend/.env"; \
		echo "  Contents:"; \
		grep -v '^#' ../backend/.env | grep -v '^$$' | sed 's/\(PASSWORD\|SECRET\)=.*/\1=********/g' | sed 's/^/    /'; \
	else \
		echo -e "\033[1;33mEnvironment File:\033[0m Not found"; \
	fi
	@echo ""
	@echo -e "\033[1;33mScripts Available:\033[0m"
	@ls -la *.sh | awk '{print "  " $$9}' || true
	@echo ""
	@echo -e "\033[1;33mBackup Directory:\033[0m"
	@if [ -d "../backups" ]; then \
		ls -la ../backups/*.sql.gz 2>/dev/null | wc -l | xargs echo "  Backups count:"; \
	else \
		echo "  Not found"; \
	fi

# Development setup (all-in-one)
dev-setup: init update-all test
	@echo -e "\033[1;32m✅ Development setup complete!\033[0m"
	@echo ""
	@echo -e "\033[1;33mQuick Start:\033[0m"
	@echo "  1. Start backend: cd ../backend && npm start"
	@echo "  2. Open frontend: http://localhost:8080"
	@echo "  3. Login with: admin / admin123"
	@echo ""

# Production preparation
prod-prep: backup secure update-admin
	@echo -e "\033[1;32m✅ Production preparation complete!\033[0m"
	@echo ""
	@echo -e "\033[1;33mNext Steps:\033[0m"
	@echo "  1. Review security settings"
	@echo "  2. Change all default passwords"
	@echo "  3. Configure regular backups"
	@echo "  4. Set up monitoring"
	@echo ""

# Status check
status:
	@echo -e "\033[1;34m[System Status]\033[0m"
	@echo ""
	@if pgrep -x "node" >/dev/null; then \
		echo -e "\033[1;32m✅ Backend: Running\033[0m"; \
	else \
		echo -e "\033[1;31m❌ Backend: Stopped\033[0m"; \
	fi
	@if pgrep -x "mysqld" >/dev/null || pgrep -x "mariadbd" >/dev/null; then \
		echo -e "\033[1;32m✅ Database: Running\033[0m"; \
	else \
		echo -e "\033[1;31m❌ Database: Stopped\033[0m"; \
	fi
	@if [ -f "../backend/.env" ]; then \
		echo -e "\033[1;32m✅ Config: Found\033[0m"; \
	else \
		echo -e "\033[1;33m⚠️  Config: Missing\033[0m"; \
	fi
	@echo ""

# Alias for common commands
setup: init
start: init
stop: backup
restart: reset
health: check
auth: test
users: update-all

# Default target
.DEFAULT_GOAL := help