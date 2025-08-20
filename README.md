# NetBox Installation Script

Este repositório contém um script automatizado para instalação do NetBox (Network Documentation and Management Tool) em servidores Ubuntu.

## 📋 Pré-requisitos

- Ubuntu 20.04, 22.04 ou 24.04 LTS
- Usuário não-root com privilégios sudo
- Conexão com internet
- Mínimo 2GB RAM e 1 vCPU
- 20GB de espaço em disco disponível

## 🚀 Instalação Rápida

### Passo 1: Clonar o Repositório

```bash
git clone https://github.com/seu-usuario/netbox-installer.git
cd netbox-installer
```

### Passo 2: Dar Permissões de Execução

```bash
chmod +x install_netbox.sh
```

### Passo 3: Executar o Script

```bash
./install_netbox.sh
```

## 📋 O que o Script Faz

O script automatiza completamente a instalação do NetBox, incluindo:

### Dependências do Sistema
- Python 3 e pip
- PostgreSQL 14+ (banco de dados)
- Redis (cache e message broker)
- Nginx (servidor web/proxy reverso)
- Bibliotecas de desenvolvimento necessárias

### Configuração do NetBox
- Criação do usuário do sistema `netbox`
- Download e instalação do NetBox v4.1.3
- Configuração do ambiente virtual Python
- Configuração automática do banco de dados
- Geração de chave secreta
- Migração do banco de dados
- Criação de superusuário (interativo)

### Serviços do Sistema
- Configuração do Gunicorn WSGI
- Serviços systemd para NetBox e NetBox-RQ
- Configuração do Nginx como proxy reverso
- Inicialização automática dos serviços

## 🛠️ Comandos para Executar no Servidor

### Método 1: Download Direto (Recomendado)

```bash
# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar git se não estiver instalado
sudo apt install git -y

# Clonar o repositório
git clone https://github.com/seu-usuario/netbox-installer.git

# Entrar no diretório
cd netbox-installer

# Dar permissões de execução
chmod +x install_netbox.sh

# Executar instalação
./install_netbox.sh
```

### Método 2: Download do Script Apenas

```bash
# Download direto do script
wget https://raw.githubusercontent.com/seu-usuario/netbox-installer/main/install_netbox.sh

# Dar permissões
chmod +x install_netbox.sh

# Executar
./install_netbox.sh
```

### Método 3: Execução em Uma Linha

```bash
curl -sSL https://raw.githubusercontent.com/seu-usuario/netbox-installer/main/install_netbox.sh | bash
```

## ⚙️ Personalização Antes da Execução

Antes de executar o script, você pode personalizar as seguintes variáveis editando o arquivo `install_netbox.sh`:

```bash
# Editar configurações
nano install_netbox.sh

# Variáveis principais para modificar:
NETBOX_VERSION="4.1.3"              # Versão do NetBox
DOMAIN_NAME="your-domain.com"       # Seu domínio
ADMIN_EMAIL="admin@your-domain.com" # Email do administrador
```

## 📊 Status dos Serviços

Após a instalação, verificar se todos os serviços estão rodando:

```bash
# Verificar status dos serviços NetBox
sudo systemctl status netbox
sudo systemctl status netbox-rq

# Verificar serviços de apoio
sudo systemctl status postgresql
sudo systemctl status redis-server
sudo systemctl status nginx

# Verificar logs em caso de problemas
sudo journalctl -u netbox -f
sudo journalctl -u netbox-rq -f
```

## 🌐 Acessar o NetBox

Após a instalação bem-sucedida:

- **Interface Web**: `http://SEU_IP_SERVIDOR`
- **Admin Panel**: `http://SEU_IP_SERVIDOR/admin/`

Use as credenciais do superusuário criadas durante a instalação.

## 📁 Estrutura de Arquivos Importantes

```
/opt/netbox/                    # Instalação principal do NetBox
├── netbox/                     # Aplicação NetBox
├── venv/                       # Ambiente virtual Python
└── gunicorn.py                 # Configuração do Gunicorn

/etc/nginx/sites-available/netbox  # Configuração do Nginx
/etc/systemd/system/netbox*        # Serviços systemd
/tmp/netbox_credentials.txt        # Credenciais (deletar após uso)
```

## 🔧 Comandos Úteis Pós-Instalação

### Gerenciamento de Serviços
```bash
# Reiniciar NetBox
sudo systemctl restart netbox netbox-rq

# Parar/Iniciar serviços
sudo systemctl stop netbox netbox-rq
sudo systemctl start netbox netbox-rq

# Ver logs em tempo real
sudo journalctl -u netbox -f
```

### Backup do Banco de Dados
```bash
# Criar backup
sudo -u postgres pg_dump netbox > netbox_backup_$(date +%Y%m%d).sql

# Restaurar backup
sudo -u postgres psql netbox < netbox_backup_YYYYMMDD.sql
```

### Atualizar NetBox
```bash
cd /opt/netbox
sudo -u netbox git pull
sudo -u netbox /opt/netbox/venv/bin/pip install -r requirements.txt
sudo -u netbox /opt/netbox/venv/bin/python3 netbox/manage.py migrate
sudo -u netbox /opt/netbox/venv/bin/python3 netbox/manage.py collectstatic --noinput
sudo systemctl restart netbox netbox-rq
```

## 🚨 Troubleshooting

### Problemas Comuns

1. **NetBox não carrega**
   ```bash
   # Verificar logs
   sudo journalctl -u netbox -n 50
   sudo journalctl -u nginx -n 50
   ```

2. **Erro de banco de dados**
   ```bash
   # Verificar status PostgreSQL
   sudo systemctl status postgresql
   
   # Testar conexão
   sudo -u netbox psql -h localhost -d netbox -U netbox
   ```

3. **Erro de Redis**
   ```bash
   # Verificar Redis
   sudo systemctl status redis-server
   redis-cli ping
   ```

4. **Problemas de permissões**
   ```bash
   # Corrigir permissões
   sudo chown -R netbox:netbox /opt/netbox
   ```

## 🔒 Segurança

Para ambiente de produção, considere:

1. **Configurar SSL/TLS**
2. **Configurar firewall (UFW)**
3. **Alterar senhas padrão**
4. **Configurar backup automático**
5. **Configurar monitoramento**

## 📞 Suporte

- [Documentação Oficial do NetBox](https://netboxlabs.com/docs/netbox/)
- [GitHub do NetBox](https://github.com/netbox-community/netbox)
- [Comunidade NetBox](https://github.com/netbox-community/netbox/discussions)

## 📄 Licença

Este script é distribuído sob a licença MIT. O NetBox é licenciado sob Apache License 2.0.

---

**⚠️ Importante**: Sempre teste em ambiente de desenvolvimento antes de usar em produção!
