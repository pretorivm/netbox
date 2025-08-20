#!/bin/bash

# NetBox Installation Script for Ubuntu
# Author: DevOps Team
# Description: Automated installation of NetBox IPAM/DCIM tool
# Compatible with Ubuntu 20.04+ and NetBox 3.6+

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
NETBOX_VERSION="3.6.9"
NETBOX_USER="netbox"
NETBOX_HOME="/opt/netbox"
POSTGRES_DB="netbox"
POSTGRES_USER="netbox"
POSTGRES_PASSWORD=$(openssl rand -base64 32)
SECRET_KEY=$(python3 -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')
DOMAIN_NAME="localhost"

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root (should run as regular user with sudo)
if [ "$EUID" -eq 0 ]; then
    error "This script should not be run as root for security reasons."
    warn "Please run as a regular user with sudo privileges."
    echo -e "${BLUE}[INFO]${NC} Example: ./install_netbox.sh"
    exit 1
fi

# Check if user has sudo privileges
if ! sudo -n true 2>/dev/null; then
    error "This user doesn't have sudo privileges."
    warn "Please run with a user that has sudo access."
    echo -e "${BLUE}[INFO]${NC} Add user to sudo group: sudo usermod -aG sudo \$USER"
    exit 1
fi

# Check Ubuntu version
check_ubuntu_version() {
    log "Checking Ubuntu version..."
    if ! lsb_release -d | grep -q "Ubuntu"; then
        error "This script is designed for Ubuntu Linux."
        exit 1
    fi
    
    UBUNTU_VERSION=$(lsb_release -rs)
    if [[ $(echo "$UBUNTU_VERSION < 20.04" | bc -l) -eq 1 ]]; then
        error "Ubuntu 20.04 or higher is required."
        exit 1
    fi
    
    log "Ubuntu $UBUNTU_VERSION detected - OK"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y wget curl git vim software-properties-common apt-transport-https ca-certificates gnupg lsb-release bc
}

# Install Python and dependencies
install_python() {
    log "Installing Python and dependencies..."
    sudo apt install -y python3 python3-pip python3-venv python3-dev build-essential libxml2-dev libxslt1-dev libffi-dev libpq-dev libssl-dev zlib1g-dev
    
    # Verify Python version
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
    log "Python $PYTHON_VERSION installed"
}

# Install and configure PostgreSQL
install_postgresql() {
    log "Installing PostgreSQL..."
    sudo apt install -y postgresql postgresql-contrib
    
    # Start and enable PostgreSQL
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    
    log "Configuring PostgreSQL database..."
    sudo -u postgres psql -c "CREATE DATABASE $POSTGRES_DB;"
    sudo -u postgres psql -c "CREATE USER $POSTGRES_USER WITH ENCRYPTED PASSWORD '$POSTGRES_PASSWORD';"
    sudo -u postgres psql -c "ALTER USER $POSTGRES_USER CREATEDB;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;"
    
    log "PostgreSQL configured successfully"
}

# Install Redis
install_redis() {
    log "Installing Redis..."
    sudo apt install -y redis-server
    
    # Configure Redis
    sudo sed -i 's/^# maxmemory <bytes>/maxmemory 512mb/' /etc/redis/redis.conf
    sudo sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
    
    sudo systemctl restart redis-server
    sudo systemctl enable redis-server
    
    log "Redis configured successfully"
}

# Create NetBox user
create_netbox_user() {
    log "Creating NetBox system user..."
    if ! id "$NETBOX_USER" &>/dev/null; then
        sudo adduser --system --group $NETBOX_USER --home $NETBOX_HOME --shell /bin/bash
        log "NetBox user created: $NETBOX_USER"
    else
        log "NetBox user already exists: $NETBOX_USER"
    fi
}

# Download and install NetBox
install_netbox() {
    log "Downloading NetBox v$NETBOX_VERSION..."
    
    # Create NetBox directory
    sudo mkdir -p $NETBOX_HOME
    cd /tmp
    
    # Download NetBox
    wget https://github.com/netbox-community/netbox/archive/v${NETBOX_VERSION}.tar.gz
    sudo tar -xzf v${NETBOX_VERSION}.tar.gz -C $NETBOX_HOME --strip-components=1
    
    # Set ownership
    sudo chown -R $NETBOX_USER:$NETBOX_USER $NETBOX_HOME
    
    log "NetBox downloaded and extracted to $NETBOX_HOME"
}

# Configure NetBox
configure_netbox() {
    log "Configuring NetBox..."
    
    # Copy configuration template
    sudo cp $NETBOX_HOME/netbox/netbox/configuration_example.py $NETBOX_HOME/netbox/netbox/configuration.py
    
    # Generate configuration
    sudo tee $NETBOX_HOME/netbox/netbox/configuration.py > /dev/null <<EOF
import os

# Database configuration
DATABASE = {
    'NAME': '$POSTGRES_DB',
    'USER': '$POSTGRES_USER',
    'PASSWORD': '$POSTGRES_PASSWORD',
    'HOST': 'localhost',
    'PORT': '',
    'CONN_MAX_AGE': 300,
}

# Redis configuration
REDIS = {
    'tasks': {
        'HOST': 'localhost',
        'PORT': 6379,
        'PASSWORD': '',
        'DATABASE': 0,
        'SSL': False,
    },
    'caching': {
        'HOST': 'localhost',
        'PORT': 6379,
        'PASSWORD': '',
        'DATABASE': 1,
        'SSL': False,
    }
}

# Security settings
SECRET_KEY = '$SECRET_KEY'
ALLOWED_HOSTS = ['localhost', '127.0.0.1', '*']

# Debug settings (set to False in production)
DEBUG = False

# Logging
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'file': {
            'level': 'INFO',
            'class': 'logging.FileHandler',
            'filename': '$NETBOX_HOME/logs/netbox.log',
        },
    },
    'loggers': {
        'django': {
            'handlers': ['file'],
            'level': 'INFO',
        },
    }
}

# Media and static files
MEDIA_ROOT = '$NETBOX_HOME/netbox/media'
STATIC_ROOT = '$NETBOX_HOME/netbox/static'

# Time zone
TIME_ZONE = 'America/Sao_Paulo'

# Email settings (configure as needed)
EMAIL = {
    'SERVER': 'localhost',
    'PORT': 25,
    'USERNAME': '',
    'PASSWORD': '',
    'USE_SSL': False,
    'USE_TLS': False,
    'TIMEOUT': 10,
    'FROM_EMAIL': 'netbox@$DOMAIN_NAME',
}
EOF

    # Set ownership of configuration
    sudo chown $NETBOX_USER:$NETBOX_USER $NETBOX_HOME/netbox/netbox/configuration.py
    sudo chmod 640 $NETBOX_HOME/netbox/netbox/configuration.py
    
    log "NetBox configuration created"
}

# Install Python dependencies
install_python_deps() {
    log "Installing Python dependencies..."
    
    # Create virtual environment as netbox user
    sudo -u $NETBOX_USER python3 -m venv $NETBOX_HOME/venv
    
    # Install requirements
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install --upgrade pip
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install -r $NETBOX_HOME/requirements.txt
    
    log "Python dependencies installed"
}

# Run Django migrations and collect static files
setup_django() {
    log "Setting up Django database and static files..."
    
    # Create logs directory
    sudo mkdir -p $NETBOX_HOME/logs
    sudo chown $NETBOX_USER:$NETBOX_USER $NETBOX_HOME/logs
    
    # Run migrations
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python $NETBOX_HOME/netbox/manage.py migrate
    
    # Collect static files
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python $NETBOX_HOME/netbox/manage.py collectstatic --no-input
    
    log "Django setup completed"
}

# Create superuser
create_superuser() {
    log "Creating NetBox superuser..."
    echo "You will now create a superuser account for NetBox."
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python $NETBOX_HOME/netbox/manage.py createsuperuser
}

# Install and configure Nginx
install_nginx() {
    log "Installing and configuring Nginx..."
    sudo apt install -y nginx
    
    # Create Nginx configuration
    sudo tee /etc/nginx/sites-available/netbox > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;
    
    client_max_body_size 25m;
    
    location /static/ {
        alias $NETBOX_HOME/netbox/static/;
    }
    
    location /media/ {
        alias $NETBOX_HOME/netbox/media/;
    }
    
    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header X-Forwarded-Host \$server_name;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOF

    # Enable site
    sudo ln -sf /etc/nginx/sites-available/netbox /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test and reload Nginx
    sudo nginx -t
    sudo systemctl reload nginx
    sudo systemctl enable nginx
    
    log "Nginx configured successfully"
}

# Install and configure Gunicorn
install_gunicorn() {
    log "Installing and configuring Gunicorn..."
    
    # Install gunicorn in virtual environment
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install gunicorn
    
    # Create Gunicorn configuration
    sudo tee $NETBOX_HOME/gunicorn.py > /dev/null <<EOF
command = '$NETBOX_HOME/venv/bin/gunicorn'
pythonpath = '$NETBOX_HOME/netbox'
bind = '127.0.0.1:8001'
workers = 5
user = '$NETBOX_USER'
timeout = 120
max_requests = 5000
max_requests_jitter = 500
EOF

    sudo chown $NETBOX_USER:$NETBOX_USER $NETBOX_HOME/gunicorn.py
    
    log "Gunicorn configured successfully"
}

# Create systemd services
create_systemd_services() {
    log "Creating systemd services..."
    
    # NetBox service
    sudo tee /etc/systemd/system/netbox.service > /dev/null <<EOF
[Unit]
Description=NetBox WSGI
Documentation=https://docs.netbox.dev/
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=$NETBOX_USER
Group=$NETBOX_USER
PIDFile=/var/tmp/netbox.pid
WorkingDirectory=$NETBOX_HOME/netbox
ExecStart=$NETBOX_HOME/venv/bin/gunicorn --config $NETBOX_HOME/gunicorn.py netbox.wsgi
ExecReload=/bin/kill -s HUP \$MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # NetBox RQ worker service
    sudo tee /etc/systemd/system/netbox-rq.service > /dev/null <<EOF
[Unit]
Description=NetBox Request Queue Worker
Documentation=https://docs.netbox.dev/
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=$NETBOX_USER
Group=$NETBOX_USER
WorkingDirectory=$NETBOX_HOME/netbox
ExecStart=$NETBOX_HOME/venv/bin/python manage.py rqworker
Restart=on-failure
RestartSec=30
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable services
    sudo systemctl daemon-reload
    sudo systemctl enable netbox netbox-rq
    
    log "Systemd services created"
}

# Start services
start_services() {
    log "Starting NetBox services..."
    sudo systemctl start netbox
    sudo systemctl start netbox-rq
    
    # Check service status
    sleep 5
    if sudo systemctl is-active --quiet netbox; then
        log "NetBox service started successfully"
    else
        error "NetBox service failed to start"
        sudo systemctl status netbox
        exit 1
    fi
    
    if sudo systemctl is-active --quiet netbox-rq; then
        log "NetBox RQ service started successfully"
    else
        error "NetBox RQ service failed to start"
        sudo systemctl status netbox-rq
        exit 1
    fi
}

# Setup firewall
setup_firewall() {
    log "Configuring UFW firewall..."
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw --force enable
        log "Firewall configured"
    else
        warn "UFW not installed, skipping firewall configuration"
    fi
}

# Main installation function
main() {
    echo "================================================"
    log "Starting NetBox installation..."
    echo "================================================"
    
    check_ubuntu_version
    update_system
    install_python
    install_postgresql
    install_redis
    create_netbox_user
    install_netbox
    configure_netbox
    install_python_deps
    setup_django
    create_superuser
    install_nginx
    install_gunicorn
    create_systemd_services
    start_services
    setup_firewall
    
    echo ""
    echo "================================================"
    log "NetBox installation completed successfully!"
    echo "================================================"
    echo ""
    log "Access NetBox at: http://$(hostname -I | awk '{print $1}')"
    log "Database: $POSTGRES_DB"
    log "Database User: $POSTGRES_USER"
    log "Database Password: $POSTGRES_PASSWORD"
    echo ""
    log "Important files:"
    log "- Configuration: $NETBOX_HOME/netbox/netbox/configuration.py"
    log "- Logs: $NETBOX_HOME/logs/netbox.log"
    log "- Virtual Environment: $NETBOX_HOME/venv"
    echo ""
    log "Useful commands:"
    log "- Check status: sudo systemctl status netbox netbox-rq"
    log "- View logs: sudo journalctl -u netbox -f"
    log "- Restart services: sudo systemctl restart netbox netbox-rq"
    echo ""
    warn "Please save the database password in a secure location!"
    echo "================================================"
}

# Run main function
main "$@"
