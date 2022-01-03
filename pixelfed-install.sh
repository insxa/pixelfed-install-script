#!/bin/bash

# simple root check
if [ `id -u ` -ne 0 ]; then
  echo "This script must be run as root.\nJust type su - and enter root password." >&2
  exit 1
fi


# upgrade system and install software
apt update
apt -y dist-upgrade
apt -y install apt-transport-https wget curl git software-properties-common dialog unzip
apt -y autoremove


# gather informations with dialogs
# open fd
exec 3>&1

# store data hostname
FULLFQDN=$(dialog --ok-label "Submit" \
    --backtitle "PixelFed installer Script" \
    --title "Install Dialog 1/4" \
    --form "We need some informations before we can start -\nNow we need to set a Hostname for this machine - this is where you will reach your PixelFed installation (e.g pixelfed.xyz or pixelfed.yourname.com).\nThis is also used for domain validation with Lets Encrypt." \
15 100 0 \
    "New Hostname: " 1 1 "$FULLFQDN" 1 15 55 0 \
2>&1 1>&3)

# close fd
exec 3>&-

# open fd
exec 3>&1

# store data instance_name
instance_name=$(dialog --ok-label "Submit" \
    --backtitle "PixelFed installer Script" \
    --title "Install Dialog 2/4" \
    --form "We need some informations before we can start -\nNow we need to set a name for your Pixelfed instance - e.g. BestPixelfedInstance." \
15 100 0 \
    "Instance Name: " 1 1 "$instance_name" 1 15 55 0 \
2>&1 1>&3)

# close fd
exec 3>&-

# open fd
exec 3>&1

# store data admin_user
admin_user=$(dialog --ok-label "Submit" \
    --backtitle "PixelFed installer Script" \
    --title "Install Dialog 3/4" \
    --form "We need some informations before we can start -\nNow we need the name for your admin user - e.g. admin or your name.\nA secure password will be generated and stored with other credentials in your root directory." \
15 100 0 \
    "Admin User: " 1 1 "$admin_user" 1 15 55 0 \
2>&1 1>&3)

# close fd
exec 3>&-

# open fd
exec 3>&1
# store data admin_mail
admin_mail=$(dialog --ok-label "Submit" \
    --backtitle "PixelFed installer Script" \
    --title "Install Dialog 4/4" \
    --form "We need some informations before we can start -\nNow we need your E-Mail address - e.g. you@example.com.\nYou will need this address to log in to your Pixelfed instance." \
15 100 0 \
    "Admin E-Mail address: " 1 1 "$admin_mail" 1 15 55 0 \
2>&1 1>&3)

# close fd
exec 3>&-

# less questions
export DEBIAN_FRONTEND="noninteractive"

# set hostname
hostnamectl set-hostname $FULLFQDN

# build mysql passwords and write a password file
mysql_root_pass=$(cat /dev/urandom | head -c 32 | base64 | cut -c -32)
mysql_user_pass=$(cat /dev/urandom | head -c 32 | base64 | cut -c -32)
echo "Mysql Root Password: $mysql_root_pass" > passwords.txt
echo "Mysql User: pixelfed" >> passwords.txt
echo "Mysql Password: $mysql_user_pass" >> passwords.txt


# add repos for current software

## nodejs for SVGO
curl -sL https://deb.nodesource.com/setup_10.x | bash -

## add nginx mainline repo
wget -q -O- https://nginx.org/keys/nginx_signing.key | apt-key add -
cat <<EOF> /etc/apt/sources.list.d/nginx-mainline.list
deb http://nginx.org/packages/mainline/debian/ stretch nginx
deb-src http://nginx.org/packages/mainline/debian/ stretch nginx
EOF

## add mysql 5.7 repo - we do it the oracle way (of course it's different)
debconf-set-selections <<< "mysql-apt-config mysql-apt-config/select-server select  mysql-5.7"
debconf-set-selections <<< "mysql-community-server  mysql-community-server/root-pass $mysql_root_pass"
debconf-set-selections <<< "mysql-community-server  mysql-community-server/re-root-pass $mysql_root_pass"
wget https://dev.mysql.com/get/mysql-apt-config_0.8.11-1_all.deb
dpkg -i mysql-apt-config_0.8.11-1_all.deb

## add php 7.4 repo
wget -q -O- https://packages.sury.org/php/apt.gpg | apt-key add -
echo "deb https://packages.sury.org/php/ stretch main" | tee /etc/apt/sources.list.d/php.list

apt update


# installations

## install fail2ban
apt -y install fail2ban

## nodejs and SVGO
apt -y install nodejs
npm install -g svgo


## install & configure UFW to allow only ssh and http/s
apt -y install ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 90/tcp
ufw allow 443/tcp

## enable UFW
ufw --force enable


## install redis server
apt -y install redis-server


## install & configure nginx
apt -y install nginx
systemctl start nginx
mkdir /etc/nginx/ssl

# generate secure dh parameters - higher values -> more security
#openssl dhparam -out /etc/nginx/ssl/dhparam.pem 1024
#openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048
openssl dhparam -out /etc/nginx/ssl/dhparam.pem 4096


### build nginx config
mkdir /etc/nginx/sites-available
mkdir /etc/nginx/sites-enabled
sed 's/user  nginx/user www-data/g' /etc/nginx/nginx.conf -i
sed 's/worker_processes  1/worker_processes  auto/g' /etc/nginx/nginx.conf -i
sed '/http {/a \    server_tokens off;'  /etc/nginx/nginx.conf -i
sed 's/#gzip  on/gzip on/g'  /etc/nginx/nginx.conf -i
sed '/conf.d/a \    include /etc/nginx/sites-enabled/*.conf;' /etc/nginx/nginx.conf -i

### create PixelFed host file for nginx
cat <<EOF > $FULLFQDN.conf
server {
  listen 80;
  listen [::]:80;
  server_name $FULLFQDN;

  location /.well-known {
    root /usr/share/nginx/html;
  }

  return 301 https://\$host\$request_uri;
}


server {
  listen 443 http2 ssl;
  listen [::]:443 http2;
  server_name $FULLFQDN;
  root /var/www/pixelfed/public;
  index index.html index.htm index.php;

  access_log /var/log/nginx/access.log;

  client_max_body_size 20M;

  add_header X-Content-Type-Options nosniff;
  add_header X-XSS-Protection "1; mode=block";
  add_header X-Robots-Tag none;
  add_header X-Download-Options noopen;
  add_header X-Permitted-Cross-Domain-Policies none;

  ssl_certificate /etc/letsencrypt/live/$FULLFQDN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$FULLFQDN/privkey.pem;
  ssl_dhparam /etc/nginx/ssl/dhparam.pem;
  ssl_session_timeout 5m;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;
  ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
  ssl_ecdh_curve secp384r1;
  ssl_session_cache shared:SSL:10m;
  add_header Strict-Transport-Security max-age=15768000;

  location /.well-known {
    root /usr/share/nginx/html;
  }

  location / {
    try_files \$uri \$uri/ /\$is_args\$args;
  }

  location ~ \.php$ {
    try_files \$uri /index.php =404;
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    fastcgi_pass unix:/run/php/php7.4-fpm.sock;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
    fastcgi_param PATH_INFO \$fastcgi_path_info;
  }

}
EOF

mv $FULLFQDN.conf /etc/nginx/sites-available/

### enable config in nginx
ln -s /etc/nginx/sites-available/$FULLFQDN.conf /etc/nginx/sites-enabled/$FULLFQDN.conf


## install and configure letsencrypt & certbot
apt -y install certbot

if [ "$(certbot certonly --webroot --agree-tos -m webmaster@$FULLFQDN -d $FULLFQDN -w /usr/share/nginx/html | grep -c "Congratulations!")" == "1" ]
then
  echo "Let's Encrypt installation okay"
else
  echo "Something went wrong while I tried to set up Let's Encrypt. Check your DNS settings."
  exit 1
fi


## restart nginx
systemctl restart nginx


## install mysql
apt -y install mysql-server

### create pixelfed user in mysql database
mysql -uroot -e "CREATE DATABASE pixelfed;"
mysql -uroot -e "CREATE USER pixelfed@localhost IDENTIFIED BY '${mysql_user_pass}';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON pixelfed.* TO 'pixelfed'@'localhost';"
mysql -uroot -e "FLUSH PRIVILEGES;"


## install php & php-fpm
apt -y install php7.4 php7.4-fpm php7.4-cli php7.4-json php7.4-mbstring php7.4-bcmath php7.4-zip php7.4-mysql php7.4-xml php-mcrypt libfreetype6 libjpeg62-turbo libpng16-16 libxpm4 libvpx4 libmagickwand-6.q16-3 optipng pngquant jpegoptim gifsicle imagemagick php7.4-gd php-imagick  php-bcmath

#### configure php-fpm
sed 's/pm.max_children = 5/pm.max_children = 25/g' /etc/php/7.4/fpm/pool.d/www.conf -i
sed 's/;pm.max_requests/pm.max_requests/g' /etc/php/7.4/fpm/pool.d/www.conf -i

### set php upload size
sed 's/upload_max_filesize = 2M/upload_max_filesize = 20M/g' /etc/php/7.4/fpm/php.ini -i
sed 's/post_max_size = 8M/post_max_size = 20M/g' /etc/php/7.4/fpm/php.ini -i
#set php max_execution_time
sed 's|max_execution_time =.*|max_execution_time = 600|g' /etc/php/7.4/fpm/php.ini -i

systemctl restart php7.4-fpm.service


## install composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer


## get pixelfed & set up
git clone https://github.com/pixelfed/pixelfed.git /var/www/pixelfed
cd /var/www/pixelfed
composer install --no-plugins --no-scripts

### build .env file
cat <<EOF > .env
#
# This is your central config file.
# Press F2 to safe and exit after your edits.
#

# SMTP server setting
MAIL_HOST=smtp.mailtrap.io
MAIL_PORT=2525
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="pixelfed@example.com"
MAIL_FROM_NAME="Pixelfed"

# open registration for new users? Set to true or false
OPEN_REGISTRATION=true

# Enable E-Mail verification when register new account? Set to true or false
ENFORCE_EMAIL_VERIFICATION=true

# use recaptcha? Set to true or false
RECAPTCHA_ENABLED=false


##### DO NOT EDIT BEHIND THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING #####


APP_KEY=
APP_DEBUG=false
APP_ENV=local
APP_NAME="$instance_name"

ADMIN_DOMAIN="$FULLFQDN"
APP_DOMAIN="$FULLFQDN"

LOG_CHANNEL=stack

APP_URL=https://$FULLFQDN

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=pixelfed
DB_USERNAME=pixelfed
DB_PASSWORD=$mysql_user_pass

MAIL_DRIVER=log

BROADCAST_DRIVER=log
CACHE_DRIVER=redis
SESSION_DRIVER=redis
SESSION_LIFETIME=120
QUEUE_DRIVER=redis

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

SESSION_DOMAIN="\${APP_DOMAIN}"
SESSION_SECURE_COOKIE=true
API_BASE="/api/1/"
API_SEARCH="/api/search"

MAX_PHOTO_SIZE=15000
MAX_CAPTION_LENGTH=150
MAX_ALBUM_LENGTH=4

MIX_PUSHER_APP_KEY="\${PUSHER_APP_KEY}"
MIX_PUSHER_APP_CLUSTER="\${PUSHER_APP_CLUSTER}"
MIX_APP_URL="\${APP_URL}"
MIX_API_BASE="\${API_BASE}"
MIX_API_SEARCH="\${API_SEARCH}"
REMOTE_FOLLOW=false
ACTIVITY_PUB=false

EOF

## let user edit the config
nano .env

## set up laravel things
php artisan key:generate
php artisan storage:link
php artisan migrate --force
sed 's/APP_ENV=local/APP_ENV=production/g' .env -i
php artisan config:cache

## install supervisor to provide horizon deamon
apt -y install supervisor
systemctl enable supervisor

## write horizon config
cat <<EOF > /etc/supervisor/conf.d/horizon.conf
[program:horizon]
process_name=%(program_name)s
command=php /var/www/pixelfed/artisan horizon
autostart=true
autorestart=true
user=www-data
redirect_stderr=true
stdout_logfile=/var/www/pixelfed/horizon.log
EOF

# configure supervisor & start horizon
supervisorctl reread
supervisorctl update
supervisorctl start horizon

chown -R www-data:www-data /var/www/pixelfed


# build admin user
apt -y install apache2-utils

## generate admin password
admin_pass=$(cat /dev/urandom | head -c 32 | base64 | cut -c -32)
echo "Pixelfed admin user: $admin_user" >> /root/passwords.txt
echo "Admin E-Mail Address: $admin_mail" >> /root/passwords.txt
echo "Pixelfed admin password: $admin_pass" >> /root/passwords.txt

### hash admin password for database
hashed_admin_pass=$(htpasswd -bnBC 10 "" $admin_pass | tr -d ':\n')

### we have to generate a openssl keypair for the admin user
ssh-keygen -b 2048 -t rsa -f sshkey -q -N ""
private_key=`cat sshkey`
public_key=`cat sshkey.pub`

### insert new user into 'users' database
mysql -uroot pixelfed -e  "INSERT INTO users (\`id\`, \`name\`, \`username\`, \`email\`, \`password\`, \`remember_token\`, \`is_admin\`, \`email_verified_at\`, \`created_at\`, \`updated_at\`, \`deleted_at\`, \`2fa_enabled\`, \`2fa_secret\`, \`2fa_backup_codes\`, \`2fa_setup_at\`) VALUES (1, '${admin_user}', '${admin_user}', '${admin_mail}', '${hashed_admin_pass}', NULL, '1', NULL, NOW(), NOW(), NULL, '0', NULL, NULL, NULL);"

### insert new user into 'profiles' database
mysql -uroot pixelfed -e  "INSERT INTO \`profiles\` (\`id\`, \`user_id\`, \`domain\`, \`username\`, \`name\`, \`bio\`, \`location\`, \`website\`, \`keybase_proof\`, \`is_private\`, \`sharedInbox\`, \`inbox_url\`, \`outbox_url\`, \`key_id\`, \`follower_url\`, \`following_url\`, \`verify_token\`, \`secret\`, \`private_key\`, \`public_key\`, \`remote_url\`, \`salmon_url\`, \`hub_url\`, \`created_at\`, \`updated_at\`, \`deleted_at\`) VALUES ('1', '1', NULL, '$admin_user', '$admin_user', NULL, NULL, NULL, NULL, '0', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '$private_key', '$public_key', NULL, NULL, NULL, NOW(), NOW(), NULL);"


# clean up
cd /root
apt -y purge apache2-utils dialog
apt -y autoremove
rm mysql-apt-config_0.8.11-1_all.deb
rm sshkey
rm sshkey.pub

echo ""
echo ""
echo "PixelFed ist installed, go to https://$FULLFQDN and log in."
echo "Your log in email is: $admin_mail"
echo "Your password is: $admin_pass"
echo "All passwords are safed in passwords.txt file in your root directory."
echo ""
