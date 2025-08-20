#!/bin/bash

# NetBox Troubleshooting Script
# This script helps diagnose and fix common NetBox installation issues

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NETBOX_USER="netbox"
NETBOX_HOME="/opt/netbox"

# Logging functions
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if Django module exists
fix_django_error() {
    echo "================================================"
    log "Fixing Django Module Error..."
    echo "================================================"
    
    # Check if virtual environment exists
    if [ ! -d "$NETBOX_HOME/venv" ]; then
        error "Virtual environment not found at $NETBOX_HOME/venv"
        log "Creating virtual environment..."
        sudo -u $NETBOX_USER python3 -m venv $NETBOX_HOME/venv
    fi
    
    # Check if Django is installed
    if ! sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python -c "import django" 2>/dev/null; then
        warn "Django not found in virtual environment"
        log "Installing Django..."
        
        # Upgrade pip first
        sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install --upgrade pip setuptools wheel
        
        # Install Django
        sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install Django
        
        # Install NetBox requirements
        if [ -f "$NETBOX_HOME/requirements.txt" ]; then
            log "Installing NetBox requirements..."
            sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install -r $NETBOX_HOME/requirements.txt
        else
            warn "Requirements file not found at $NETBOX_HOME/requirements.txt"
        fi
    else
        log "Django is already installed"
    fi
    
    # Verify Django installation
    DJANGO_VERSION=$(sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python -c "import django; print(django.get_version())" 2>/dev/null || echo "Unknown")
    log "Django version: $DJANGO_VERSION"
}

# Fix permissions
fix_permissions() {
    echo "================================================"
    log "Fixing File Permissions..."
    echo "================================================"
    
    # Check if netbox user exists
    if ! id "$NETBOX_USER" &>/dev/null; then
        error "NetBox user '$NETBOX_USER' does not exist"
        log "Creating NetBox user..."
        sudo adduser --system --group $NETBOX_USER --home $NETBOX_HOME --shell /bin/bash
    fi
    
    # Fix ownership
    log "Setting correct ownership..."
    sudo chown -R $NETBOX_USER:$NETBOX_USER $NETBOX_HOME
    
    # Fix permissions
    log "Setting correct permissions..."
    sudo chmod 755 $NETBOX_HOME
    sudo chmod -R 755 $NETBOX_HOME/netbox
    
    if [ -f "$NETBOX_HOME/netbox/netbox/configuration.py" ]; then
        sudo chmod 640 $NETBOX_HOME/netbox/netbox/configuration.py
    fi
    
    # Create required directories
    sudo mkdir -p $NETBOX_HOME/netbox/media
    sudo mkdir -p $NETBOX_HOME/logs
    sudo chown -R $NETBOX_USER:$NETBOX_USER $NETBOX_HOME/netbox/media
    sudo chown -R $NETBOX_USER:$NETBOX_USER $NETBOX_HOME/logs
    
    log "Permissions fixed successfully"
}

# Reinstall Python dependencies
reinstall_dependencies() {
    echo "================================================"
    log "Reinstalling Python Dependencies..."
    echo "================================================"
    
    if [ ! -f "$NETBOX_HOME/requirements.txt" ]; then
        error "Requirements file not found at $NETBOX_HOME/requirements.txt"
        return 1
    fi
    
    # Remove existing virtual environment
    if [ -d "$NETBOX_HOME/venv" ]; then
        warn "Removing existing virtual environment..."
        sudo rm -rf $NETBOX_HOME/venv
    fi
    
    # Create new virtual environment
    log "Creating new virtual environment..."
    sudo -u $NETBOX_USER python3 -m venv $NETBOX_HOME/venv
    
    # Install dependencies
    log "Installing Python dependencies..."
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install --upgrade pip setuptools wheel
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install Django
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install -r $NETBOX_HOME/requirements.txt
    
    log "Dependencies reinstalled successfully"
}

# Check configuration file
check_configuration() {
    echo "================================================"
    log "Checking Configuration..."
    echo "================================================"
    
    CONFIG_FILE="$NETBOX_HOME/netbox/netbox/configuration.py"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
        
        if [ -f "$NETBOX_HOME/netbox/netbox/configuration_example.py" ]; then
            log "Creating configuration from example..."
            sudo cp $NETBOX_HOME/netbox/netbox/configuration_example.py $CONFIG_FILE
            sudo chown $NETBOX_USER:$NETBOX_USER $CONFIG_FILE
            sudo chmod 640 $CONFIG_FILE
            warn "Please edit $CONFIG_FILE with your settings"
        else
            error "Example configuration also not found"
            return 1
        fi
    else
        log "Configuration file exists"
    fi
    
    # Test configuration syntax
    log "Testing configuration syntax..."
    if sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python -c "
import sys
sys.path.insert(0, '$NETBOX_HOME/netbox')
try:
    from netbox import configuration
    print('Configuration syntax is valid')
except Exception as e:
    print(f'Configuration error: {e}')
    sys.exit(1)
" 2>/dev/null; then
        log "Configuration syntax is valid"
    else
        error "Configuration has syntax errors"
        return 1
    fi
}

# Check database connection
check_database() {
    echo "================================================"
    log "Checking Database Connection..."
    echo "================================================"
    
    # Check PostgreSQL service
    if ! sudo systemctl is-active --quiet postgresql; then
        warn "PostgreSQL service is not running"
        log "Starting PostgreSQL..."
        sudo systemctl start postgresql
    else
        log "PostgreSQL service is running"
    fi
    
    # Test database connection (basic check)
    if sudo -u postgres psql -l | grep -q netbox; then
        log "NetBox database exists"
    else
        warn "NetBox database not found"
        log "You may need to create the database manually"
    fi
}

# Check Redis connection
check_redis() {
    echo "================================================"
    log "Checking Redis Connection..."
    echo "================================================"
    
    # Check Redis service
    if ! sudo systemctl is-active --quiet redis-server; then
        warn "Redis service is not running"
        log "Starting Redis..."
        sudo systemctl start redis-server
    else
        log "Redis service is running"
    fi
    
    # Test Redis connection
    if redis-cli ping | grep -q PONG; then
        log "Redis connection successful"
    else
        warn "Redis connection failed"
    fi
}

# Run Django migrations
run_migrations() {
    echo "================================================"
    log "Running Django Migrations..."
    echo "================================================"
    
    cd $NETBOX_HOME/netbox
    
    # Check migrations
    log "Checking for pending migrations..."
    if sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python manage.py showmigrations --plan | grep -q "\[ \]"; then
        log "Running migrations..."
        sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python manage.py migrate
    else
        log "No pending migrations"
    fi
    
    # Collect static files
    log "Collecting static files..."
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python manage.py collectstatic --no-input
}

# Check services status
check_services() {
    echo "================================================"
    log "Checking Service Status..."
    echo "================================================"
    
    services=("postgresql" "redis-server" "netbox" "netbox-rq" "nginx")
    
    for service in "${services[@]}"; do
        if sudo systemctl is-active --quiet $service; then
            log "$service: Running"
        else
            warn "$service: Not running"
        fi
    done
}

# Show logs
show_logs() {
    echo "================================================"
    log "Recent NetBox Logs..."
    echo "================================================"
    
    # Show systemd logs
    log "NetBox service logs (last 20 lines):"
    sudo journalctl -u netbox --no-pager -n 20
    
    echo ""
    log "NetBox RQ service logs (last 10 lines):"
    sudo journalctl -u netbox-rq --no-pager -n 10
    
    # Show application logs if they exist
    if [ -f "$NETBOX_HOME/logs/netbox.log" ]; then
        echo ""
        log "Application logs (last 10 lines):"
        sudo tail -n 10 $NETBOX_HOME/logs/netbox.log
    fi
}

# Test NetBox functionality
test_netbox() {
    echo "================================================"
    log "Testing NetBox Functionality..."
    echo "================================================"
    
    cd $NETBOX_HOME/netbox
    
    # Test Django check
    log "Running Django system check..."
    if sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python manage.py check; then
        log "Django system check passed"
    else
        error "Django system check failed"
        return 1
    fi
    
    # Test database connection
    log "Testing database connection..."
    if sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python manage.py shell -c "
from django.db import connection
cursor = connection.cursor()
cursor.execute('SELECT 1')
print('Database connection successful')
"; then
        log "Database connection test passed"
    else
        error "Database connection test failed"
        return 1
    fi
}

# Menu system
show_menu() {
    echo ""
    echo "================================================"
    echo "NetBox Troubleshooting Menu"
    echo "================================================"
    echo "1. Fix Django Module Error"
    echo "2. Fix File Permissions"
    echo "3. Reinstall Dependencies"
    echo "4. Check Configuration"
    echo "5. Check Database"
    echo "6. Check Redis"
    echo "7. Run Migrations"
    echo "8. Check Services Status"
    echo "9. Show Recent Logs"
    echo "10. Test NetBox Functionality"
    echo "11. Run All Checks"
    echo "12. Exit"
    echo "================================================"
}

# Run all checks
run_all_checks() {
    log "Running all troubleshooting checks..."
    fix_django_error
    fix_permissions
    check_configuration
    check_database
    check_redis
    check_services
    test_netbox
    log "All checks completed!"
}

# Main menu loop
main() {
    if [ "$EUID" -eq 0 ]; then
        error "This script should not be run as root"
        exit 1
    fi
    
    while true; do
        show_menu
        read -p "Select an option (1-12): " choice
        
        case $choice in
            1) fix_django_error ;;
            2) fix_permissions ;;
            3) reinstall_dependencies ;;
            4) check_configuration ;;
            5) check_database ;;
            6) check_redis ;;
            7) run_migrations ;;
            8) check_services ;;
            9) show_logs ;;
            10) test_netbox ;;
            11) run_all_checks ;;
            12) log "Exiting..."; exit 0 ;;
            *) error "Invalid option. Please try again." ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"
