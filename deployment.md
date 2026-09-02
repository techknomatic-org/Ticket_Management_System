# GLPI Ticket Management System - DigitalOcean Deployment Guide

This guide provides step-by-step instructions for deploying the **Techknomatic Ticket Management System (GLPI 11)** to **DigitalOcean** in a secure, production-grade environment.

---

## Deployment Architecture Overview

* **Cloud Provider**: DigitalOcean
* **Operating System**: Ubuntu 24.04 LTS or 22.04 LTS Droplet
* **Web Server**: Nginx (Reverse Proxy / FastCGI with HTTP/2 and TLS 1.3)
* **Backend Runtime**: PHP 8.4 or 8.3 (PHP-FPM)
* **Database**: MySQL 8.0 / MariaDB 10.11+ (Droplet-hosted or DigitalOcean Managed Database)
* **SSL/TLS**: Let's Encrypt automated certificate renewal via Certbot
* **Document Root**: `/var/www/ticket-system/public` (Important: Only `/public` is exposed)
* **Automation**: Systemd Cron for ticket queues, notifications, and scheduled tasks

---

## Prerequisite Checklist

- [ ] A DigitalOcean account with billing enabled.
- [ ] A domain name (e.g., `tickets.yourdomain.com`) with an **A record** pointing to your Droplet's IPv4 address.
- [ ] SSH key pair generated on your local machine and added to DigitalOcean.
- [ ] Access to the GitHub repository: `https://github.com/techknomatic-org/Ticket-Management-System.git`

---

## Production LEMP Stack Deployment (Ubuntu 24.04 Droplet)

### Step 1: Provision DigitalOcean Droplet

1. Go to **DigitalOcean Cloud Console** -> **Droplets** -> **Create Droplet**.
2. **Region**: Choose the datacenter closest to your primary users.
3. **OS**: **Ubuntu 24.04 LTS (x64)**.
4. **Droplet Type**:
   * **Minimum**: Regular General Purpose, 2 GB RAM / 1 vCPU ($12/month).
   * **Recommended for Teams**: Premium Intel or AMD, 4 GB RAM / 2 vCPUs ($24 - $28/month).
5. **Authentication**: Select your **SSH Key**.
6. **Hostname**: e.g., `ticket-system-prod`.
7. Click **Create Droplet**.

---

### Step 2: Initial Server Setup & Firewall

SSH into your Droplet as root:
```bash
ssh root@<DROPLET_IP>
```

Update system packages:
```bash
apt update && apt upgrade -y
```

Create a non-root administrative user:
```bash
adduser deployer
usermod -aG sudo deployer

# Copy SSH keys to new user
rsync --archive --chown=deployer:deployer ~/.ssh /home/deployer
```

Configure **UFW Firewall**:
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

---

### Step 3: Install PHP 8.4 and Required Extensions

GLPI requires specific PHP extensions for ticket routing, authentication, and document processing:

```bash
apt install -y software-properties-common ca-certificates apt-transport-https
add-apt-repository ppa:ondrej/php -y
apt update

apt install -y \
    php8.4-fpm \
    php8.4-cli \
    php8.4-mysql \
    php8.4-curl \
    php8.4-gd \
    php8.4-intl \
    php8.4-mbstring \
    php8.4-xml \
    php8.4-zip \
    php8.4-bz2 \
    php8.4-ldap \
    php8.4-opcache \
    php8.4-soap \
    php8.4-sodium \
    php8.4-bcmath \
    php8.4-readline \
    unzip \
    git \
    curl
```

Tune PHP configuration for GLPI:
Edit `/etc/php/8.4/fpm/php.ini`:
```ini
memory_limit = 512M
upload_max_filesize = 100M
post_max_size = 100M
max_execution_time = 300
max_input_time = 300
date.timezone = UTC
session.cookie_httponly = On
session.use_strict_mode = 1
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
```

Restart PHP-FPM:
```bash
systemctl restart php8.4-fpm
```

---

### Step 4: Install Database (MariaDB or MySQL)

*(Skip if using DigitalOcean Managed Database)*

```bash
apt install -y mariadb-server mariadb-client
systemctl enable --now mariadb
mysql_secure_installation
```

Log in to MySQL:
```bash
mysql -u root -p
```

Create GLPI database, dedicated user, and grant privileges:
```sql
CREATE DATABASE ticketing_system CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'glpi_user'@'localhost' IDENTIFIED BY 'STRONG_SECRET_PASSWORD_HERE';
GRANT ALL PRIVILEGES ON ticketing_system.* TO 'glpi_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

---

### Step 5: Install Node.js & Composer

Install **Composer**:
```bash
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
```

Install **Node.js 20 LTS**:
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
```

---

### Step 6: Deploy Codebase & Build Assets

Clone the repository into `/var/www/ticket-system`:
```bash
git clone https://github.com/techknomatic-org/Ticket-Management-System.git /var/www/ticket-system
cd /var/www/ticket-system
```

Install PHP dependencies:
```bash
composer install --no-dev --optimize-autoloader --no-interaction
```

Install NPM packages and build frontend assets:
```bash
npm ci --omit=dev
npm run build:pack
npm run build:vue
php bin/console tools:locales:compile --allow-superuser
```

---

### Step 7: Configure Database & Generate Encryption Keys

1. Create GLPI database configuration file at `/var/www/ticket-system/config/config_db.php`:
```php
<?php
class DB extends DBmysql {
   public $dbhost = '127.0.0.1';
   public $dbuser = 'glpi_user';
   public $dbpassword = 'STRONG_SECRET_PASSWORD_HERE';
   public $dbdefault = 'ticketing_system';
   public $use_utf8mb4 = true;
   public $allow_datetime = false;
   public $allow_signed_keys = false;
}
```

2. Initialize the database schema:
```bash
# If starting fresh:
php bin/console db:install --db-host=127.0.0.1 --db-name=ticketing_system --db-user=glpi_user --db-password='STRONG_SECRET_PASSWORD_HERE' --no-interaction --force

# OR if migrating existing data from local dump:
mysql -u glpi_user -p ticketing_system < /tmp/local_dump.sql
php bin/console db:update --no-interaction
```

3. Ensure security keys exist:
```bash
php bin/console glpi:security:change_key --no-interaction
```

---

### Step 8: Set Proper File Permissions

```bash
# Ensure required directories exist
mkdir -p /var/www/ticket-system/files/{_cache,_cron,_dumps,_graphs,_inventories,_locales,_lock,_log,_pictures,_plugins,_rss,_sessions,_themes,_tmp,_uploads}
mkdir -p /var/www/ticket-system/marketplace

# Assign ownership to Nginx/PHP user
chown -R www-data:www-data /var/www/ticket-system

# Restrict permissions
find /var/www/ticket-system -type d -exec chmod 755 {} \;
find /var/www/ticket-system -type f -exec chmod 644 {} \;

# Writable directories for web user
chmod -R 775 /var/www/ticket-system/files
chmod -R 775 /var/www/ticket-system/config
chmod -R 775 /var/www/ticket-system/marketplace
```

---

### Step 9: Configure Nginx

Install Nginx:
```bash
apt install -y nginx
```

Create server block `/etc/nginx/sites-available/ticket-system`:
```nginx
server {
    listen 80;
    server_name tickets.yourdomain.com;

    # Important: Document root MUST point to /public
    root /var/www/ticket-system/public;
    index index.php index.html;

    client_max_body_size 100M;
    client_body_timeout 120s;

    access_log /var/log/nginx/tickets_access.log;
    error_log /var/log/nginx/tickets_error.log;

    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Frame-Options SAMEORIGIN;
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    location / {
        try_files $uri /index.php$is_args$args;
    }

    location ~ ^/index\.php(/|$) {
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_read_timeout 300s;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 256 16k;
        fastcgi_busy_buffers_size 256k;
        internal;
    }

    # Deny access to hidden files and sensitive directories
    location ~ /\. {
        deny all;
    }

    location ~ \.(ini|log|conf)$ {
        deny all;
    }
}
```

Enable site and test configuration:
```bash
ln -s /etc/nginx/sites-available/ticket-system /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
```

---

### Step 10: Setup SSL with Let's Encrypt (Certbot)

Install Certbot:
```bash
apt install -y certbot python3-certbot-nginx
```

Obtain SSL certificate and automatically configure Nginx:
```bash
certbot --nginx -d tickets.yourdomain.com --agree-tos --redirect -m admin@yourdomain.com
```

Verify automated renewal:
```bash
systemctl status certbot.timer
```

---

### Step 11: Configure System Cron (Automated Ticket Processing)

GLPI requires a scheduled cron to process queued notifications, SLA escalations, mail collectors, and automatic ticket assignment.

Edit crontab for `www-data`:
```bash
crontab -u www-data -e
```

Add the following entry to execute every minute:
```crontab
* * * * * /usr/bin/php /var/www/ticket-system/bin/console cron:run --force >/dev/null 2>&1
```

In the GLPI Web interface:
Go to **Setup** -> **Automatic actions** -> Change **Run mode** from `GLPI` to `CLI`.

---

## Migrating Existing Local Database to DigitalOcean

To transfer your current local database (`ticketing_system`) to DigitalOcean:

### 1. Export locally (Windows):
```powershell
mysqldump -u root -p -h 127.0.0.1 ticketing_system > local_tickets_backup.sql
```

### 2. Copy to DigitalOcean Droplet via SCP:
```bash
scp local_tickets_backup.sql deployer@<DROPLET_IP>:/tmp/
```

### 3. Import on Droplet:
```bash
mysql -u glpi_user -p ticketing_system < /tmp/local_tickets_backup.sql
```

### 4. Copy encryption key files:
Copy `config/glpicrypt.key`, `config/oauth.pem`, `config/oauth.pub` to `/var/www/ticket-system/config/` and ensure ownership:
```bash
chown -R www-data:www-data /var/www/ticket-system/config
chmod 600 /var/www/ticket-system/config/glpicrypt.key
chmod 600 /var/www/ticket-system/config/oauth.pem
```

---

## Production Verification Checklist

Run system diagnostics via CLI:
```bash
cd /var/www/ticket-system
php bin/console system:check_requirements
php bin/console system:status
```

Expected output should confirm:
* `glpi: OK`
* `db: OK`
* `crontasks: OK`
* `filesystem: OK`

---

## Security Best Practices on DigitalOcean

1. **DigitalOcean Cloud Firewalls**: Create a Cloud Firewall in the DigitalOcean console and attach it to your Droplet. Allow inbound traffic only on ports 22, 80, and 443.
2. **Droplet Automated Backups**: Enable DigitalOcean weekly/daily automated backups under Droplet -> **Backups**.
3. **Fail2Ban**:
   ```bash
   apt install -y fail2ban
   systemctl enable --now fail2ban
   ```
4. **Disable GLPI Install Directory**: Once installed, ensure `/install/install.php` is protected or removed.
5. **Change Default Passwords Immediately**:
   - `glpi` (Super-Admin)
   - `tech` (Technician)
   - `normal` (Standard User)
   - `post-only` (Helpdesk Submission)
