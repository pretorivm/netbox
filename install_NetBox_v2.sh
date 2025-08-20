#!/bin/bash

# NetBox Installation Script for Ubuntu
# Compatible with Ubuntu 20.04, 22.04, and 24.04
# Author: NetBox Installation Automation
# Version: 1.0
# Description: Complete automated installation of NetBox IPAM/DCIM tool

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
NETBOX_VERSION="4.1.3"
NETBOX_USER="netbox"
NETBOX_HOME="/opt/netbox"
DB_NAME="netbox"
DB_USER="netbox"
DOMAIN_NAME="your-domain.com"  # Change this to your domain
ADMIN_EMAIL="admin@your-domain.com"  # Change this to your email

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root for security reasons."
        print_warning "Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Function to check Ubuntu version
check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        print_error "This script is designed for Ubuntu only"
        exit 1
    fi
    
    print_status "Detected Ubuntu $VERSION"
}

# Function to generate random password
generate_password() {
    openssl rand -base64 32
}

# Function to update system
update_system() {
    print_status "Updating system packages..."
    sudo apt update -y
    sudo apt upgrade -y
    print_success "System updated successfully"
}

# Function to install system dependencies
install_dependencies() {
    print_status "Installing system dependencies..."
    sudo apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        libxml2-dev \
        libxslt1-dev \
        libffi-dev \
        libpq-dev \
        libssl-dev \
        zlib1g-dev \
        libjpeg-dev \
        uuid-dev \
        git \
        nginx \
        supervisor \
        curl \
        wget \
        unzip
    print_success "System dependencies installed"
}

# Function to install and configure PostgreSQL
setup_postgresql() {
    print_status "Installing and configuring PostgreSQL..."
    sudo apt install -y postgresql postgresql-contrib
    
    # Start and enable PostgreSQL
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    
    # Generate database password
    DB_PASSWORD=$(generate_password)
    
    # Create database and user
    print_status "Creating NetBox database and user..."
    sudo -u postgres psql << EOF
CREATE DATABASE $DB_NAME;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
ALTER ROLE $DB_USER SET client_encoding TO 'utf8';
ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';
ALTER ROLE $DB_USER SET timezone TO 'UTC';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
ALTER USER $DB_USER CREATEDB;
\q
EOF
    
    # Save database credentials
    echo "DB_PASSWORD=$DB_PASSWORD" >> /tmp/netbox_credentials.txt
    print_success "PostgreSQL configured successfully"
}

# Function to install and configure Redis
setup_redis() {
    print_status "Installing and configuring Redis..."
    sudo apt install -y redis-server
    
    # Configure Redis
    sudo sed -i 's/^# maxmemory <bytes>/maxmemory 512mb/' /etc/redis/redis.conf
    sudo sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
    
    # Start and enable Redis
    sudo systemctl start redis-server
    sudo systemctl enable redis-server
    
    print_success "Redis configured successfully"
}

# Function to create NetBox user
create_netbox_user() {
    print_status "Creating NetBox system user..."
    sudo useradd --system --shell /bin/bash --home-dir $NETBOX_HOME --create-home $NETBOX_USER
    print_success "NetBox user created"
}

# Function to download and install NetBox
install_netbox() {
    print_status "Downloading and installing NetBox v$NETBOX_VERSION..."
    
    # Download NetBox
    cd /tmp
    wget https://github.com/netbox-community/netbox/archive/refs/tags/v$NETBOX_VERSION.tar.gz
    sudo tar -xzf v$NETBOX_VERSION.tar.gz -C /opt
    sudo mv /opt/netbox-$NETBOX_VERSION $NETBOX_HOME
    sudo chown -R $NETBOX_USER:$NETBOX_USER $NETBOX_HOME
    
    print_success "NetBox downloaded and extracted"
}

# Function to create Python virtual environment
setup_python_environment() {
    print_status "Setting up Python virtual environment..."
    sudo -u $NETBOX_USER python3 -m venv $NETBOX_HOME/venv
    
    # Upgrade pip and install wheel
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install --upgrade pip wheel
    
    # Install NetBox requirements
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/pip install -r $NETBOX_HOME/requirements.txt
    
    print_success "Python environment configured"
}

# Function to configure NetBox
configure_netbox() {
    print_status "Configuring NetBox..."
    
    # Generate secret key
    SECRET_KEY=$(sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python3 $NETBOX_HOME/netbox/generate_secret_key.py)
    
    # Get database password
    source /tmp/netbox_credentials.txt
    
    # Create configuration file
    sudo -u $NETBOX_USER tee $NETBOX_HOME/netbox/netbox/configuration.py > /dev/null << EOF
import os

# Database configuration
DATABASE = {
    'NAME': '$DB_NAME',
    'USER': '$DB_USER',
    'PASSWORD': '$DB_PASSWORD',
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

# Security
SECRET_KEY = '$SECRET_KEY'
ALLOWED_HOSTS = ['*']

# Email configuration (optional)
EMAIL = {
    'SERVER': 'localhost',
    'PORT': 25,
    'USERNAME': '',
    'PASSWORD': '',
    'USE_SSL': False,
    'USE_TLS': False,
    'TIMEOUT': 10,
    'FROM_EMAIL': '$ADMIN_EMAIL',
}

# Logging
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'normal': {
            'format': '%(asctime)s.%(msecs)03d %(levelname)-7s %(name)s %(message)s',
            'datefmt': '%H:%M:%S',
        },
    },
    'handlers': {
        'normal': {
            'level': 'INFO',
            'class': 'logging.StreamHandler',
            'formatter': 'normal',
        },
    },
    'loggers': {
        'django': {
            'handlers': ['normal'],
            'level': 'INFO',
        },
        'netbox': {
            'handlers': ['normal'],
            'level': 'DEBUG',
        },
    }
}

# Optional settings
TIME_ZONE = 'UTC'
DATE_FORMAT = 'N j, Y'
SHORT_DATE_FORMAT = 'Y-m-d'
TIME_FORMAT = 'g:i a'
SHORT_TIME_FORMAT = 'H:i:s'
DATETIME_FORMAT = 'N j, Y g:i a'
SHORT_DATETIME_FORMAT = 'Y-m-d H:i'
EOF
    
    # Save credentials
    echo "SECRET_KEY=$SECRET_KEY" >> /tmp/netbox_credentials.txt
    print_success "NetBox configuration created"
}

# Function to run NetBox migrations
run_migrations() {
    print_status "Running database migrations..."
    cd $NETBOX_HOME/netbox
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python3 manage.py migrate
    
    print_status "Collecting static files..."
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python3 manage.py collectstatic --noinput
    
    print_success "Database migrations completed"
}

# Function to create superuser
create_superuser() {
    print_status "Creating NetBox superuser..."
    print_warning "You will need to enter superuser details:"
    
    cd $NETBOX_HOME/netbox
    sudo -u $NETBOX_USER $NETBOX_HOME/venv/bin/python3 manage.py createsuperuser
    
    print_success "Superuser created"
}

# Function to configure Gunicorn
setup_gunicorn() {
    print_status "Configuring Gunicorn..."
    
    # Create Gunicorn configuration
    sudo -u $NETBOX_USER tee $NETBOX_HOME/gunicorn.py > /dev/null << 'EOF'
command = '/opt/netbox/venv/bin/gunicorn'
pythonpath = '/opt/netbox/netbox'
bind = '127.0.0.1:8001'
workers = 5
user = 'netbox'
timeout = 120
max_requests = 5000
max_requests_jitter = 500
preload_app = True
EOF
    
    print_success "Gunicorn configured"
}

# Function to configure systemd services
setup_systemd() {
    print_status "Setting up systemd services..."
    
    # NetBox service
    sudo tee /etc/systemd/system/netbox.service > /dev/null << 'EOF'
[Unit]
Description=NetBox WSGI
Documentation=https://netboxlabs.com/docs/netbox/
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=netbox
Group=netbox
PIDFile=/var/tmp/netbox.pid
WorkingDirectory=/opt/netbox/netbox
ExecStart=/opt/netbox/venv/bin/gunicorn --pid /var/tmp/netbox.pid --pythonpath /opt/netbox/netbox --config /opt/netbox/gunicorn.py netbox.wsgi
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=90
KillMode=mixed
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    # NetBox RQ worker service
    sudo tee /etc/systemd/system/netbox-rq.service > /dev/null << 'EOF'
[Unit]
Description=NetBox Request Queue Worker
Documentation=https://netboxlabs.com/docs/netbox/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=netbox
Group=netbox
WorkingDirectory=/opt/netbox/netbox
ExecStart=/opt/netbox/venv/bin/python3 /opt/netbox/netbox/manage.py rqworker
Restart=on-failure
RestartSec=30
KillMode=mixed
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable services
    sudo systemctl daemon-reload
    sudo systemctl enable netbox netbox-rq
    
    print_success "Systemd services configured"
}

# Function to configure Nginx
setup_nginx() {
    print_status "Configuring Nginx..."
    
    # Remove default site
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Create NetBox site configuration
    sudo tee /etc/nginx/sites-available/netbox > /dev/null << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME _;

    client_max_body_size 25m;

    location /static/ {
        alias /opt/netbox/netbox/static/;
    }

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header X-Forwarded-Host \$server_name;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        add_header P3P 'CP="ALL DSP COR PSAa PSDa OUR NOR ONL UNI COM NAV"';
    }
}
EOF
    
    # Enable NetBox site
    sudo ln -sf /etc/nginx/sites-available/netbox /etc/nginx/sites-enabled/
    
    # Test and reload Nginx
    sudo nginx -t && sudo systemctl reload nginx
    
    print_success "Nginx configured"
}

# Function to start services
start_services() {
    print_status "Starting NetBox services..."
    sudo systemctl start netbox netbox-rq
    sudo systemctl restart nginx
    
    print_success "Services started"
}

# Function to display final information
show_final_info() {
    print_success "NetBox installation completed successfully!"
    echo ""
    print_status "Installation Summary:"
    echo "- NetBox version: $NETBOX_VERSION"
    echo "- Installation directory: $NETBOX_HOME"
    echo "- Database: PostgreSQL ($DB_NAME)"
    echo "- Cache: Redis"
    echo "- Web server: Nginx"
    echo ""
    print_status "Service Status:"
    sudo systemctl is-active netbox && echo "✓ NetBox: Active" || echo "✗ NetBox: Inactive"
    sudo systemctl is-active netbox-rq && echo "✓ NetBox RQ: Active" || echo "✗ NetBox RQ: Inactive"
    sudo systemctl is-active nginx && echo "✓ Nginx: Active" || echo "✗ Nginx: Inactive"
    sudo systemctl is-active postgresql && echo "✓ PostgreSQL: Active" || echo "✗ PostgreSQL: Inactive"
    sudo systemctl is-active redis-server && echo "✓ Redis: Active" || echo "✗ Redis: Inactive"
    echo ""
    print_status "Access Information:"
    echo "- Web Interface: http://$(hostname -I | awk '{print $1}') or http://$DOMAIN_NAME"
    echo "- Admin Panel: http://$(hostname -I | awk '{print $1}')/admin/"
    echo ""
    print_warning "Important Files:"
    echo "- Configuration: $NETBOX_HOME/netbox/netbox/configuration.py"
    echo "- Credentials: /tmp/netbox_credentials.txt (delete after noting down)"
    echo "- Logs: /var/log/nginx/ and journalctl -u netbox -u netbox-rq"
    echo ""
    print_warning "Next Steps:"
    echo "1. Access NetBox web interface using the URL above"
    echo "2. Log in with the superuser account you created"
    echo "3. Configure SSL/TLS certificate for production use"
    echo "4. Review and customize configuration as needed"
    echo "5. Delete /tmp/netbox_credentials.txt after saving credentials securely"
    echo ""
    print_status "For support and documentation, visit: https://netboxlabs.com/docs/netbox/"
}

# Function to handle cleanup on error
cleanup() {
    print_error "Installation failed. Cleaning up..."
    sudo systemctl stop netbox netbox-rq 2>/dev/null || true
    sudo systemctl disable netbox netbox-rq 2>/dev/null || true
    rm -f /tmp/netbox_credentials.txt 2>/dev/null || true
}

# Main installation function
main() {
    print_status "Starting NetBox installation..."
    echo "================================================"
    
    # Set trap for cleanup on error
    trap cleanup ERR
    
    # Pre-installation checks
    check_root
    check_ubuntu_version
    
    # Installation steps
    update_system
    install_dependencies
    setup_postgresql
    setup_redis
    create_netbox_user
    install_netbox
    setup_python_environment
    configure_netbox
    run_migrations
    create_superuser
    setup_gunicorn
    setup_systemd
    setup_nginx
    start_services
    show_final_info
    
    print_success "NetBox installation completed successfully!"
}

# Run main function
main "$@"
