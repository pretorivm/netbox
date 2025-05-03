#!/bin/bash

echo "Instalando dependências..."
apt update && apt upgrade -y
apt install -y python3 python3-pip python3-venv python3-dev build-essential \
libpq-dev libffi-dev libssl-dev zlib1g-dev libjpeg-dev libxml2-dev libxslt1-dev \
libldap2-dev libsasl2-dev redis-server postgresql nginx git

echo "Criando usuário netbox..."
adduser --system --group netbox

echo "Clonando repositório..."
cd /opt
git clone -b master https://github.com/netbox-community/netbox.git
chown -R netbox:netbox /opt/netbox

echo "Configurando banco de dados..."
sudo -u postgres psql -c "CREATE DATABASE netbox;"
sudo -u postgres psql -c "CREATE USER netbox WITH PASSWORD 'SenhaForte123!';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE netbox TO netbox;"

echo "Criando ambiente virtual e instalando Python requirements..."
cd /opt/netbox
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "Configurando ambiente NetBox..."
cd /opt/netbox/netbox
cp configuration_example.py configuration.py
cp environ-example .env

SECRET_KEY=$(python3 generate_secret_key.py)
cat <<EOF > .env
ALLOWED_HOSTS=localhost 127.0.0.1
DB_NAME=netbox
DB_USER=netbox
DB_PASSWORD=SenhaForte123!
SECRET_KEY=$SECRET_KEY
EOF

echo "Migrando banco e criando superusuário..."
python3 manage.py migrate
echo "Crie o superusuário manualmente:"
python3 manage.py createsuperuser
python3 manage.py collectstatic --no-input

echo "Ativando serviço NetBox..."
cp /opt/netbox/contrib/gunicorn.py /opt/netbox/gunicorn.py
cp /opt/netbox/contrib/netbox.service /etc/systemd/system/netbox.service
systemctl daemon-reexec
systemctl enable --now netbox

echo "Configurando NGINX..."
cp /opt/netbox/contrib/nginx.conf /etc/nginx/sites-available/netbox
ln -s /etc/nginx/sites-available/netbox /etc/nginx/sites-enabled/
systemctl restart nginx

echo "✅ NetBox instalado com sucesso. Acesse: http://<SEU_IP>"
