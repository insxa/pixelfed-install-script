# PixelFed bash installer
This script is intended to install PixelFed on a freshly installed Debian 9 (Stretch) without Docker. Prerequisites that must be met before you run this script:
- access to root account, this script must run by root user, _not sudo_.
- fresh install and no databases or webservers installed.
- a DNS entry pointing to your webserver otherwise Let's Encrypt installation
will fail and stop the installation process.
- and of course an active and configured connection to the internet.

If you don't understand something about the above or don't know how to set it up, you should consider whether a hosted version of PixelFed wouldn't be better for you. Servers on the Internet are no toys and can do quite a lot of damage if operated by people who don't know what they're doing.

### This script will install a *complete* PixelFed instance server, therefore we need:
- a Database (Mysql 5.7)
- a Webserver (nginx - mainline version)
  - To provide encrypted communication, this script sets up [Let's Encrypt](https://letsencrypt.org)
  - to automate renew Let's Encrypt certificates, certbot will be installed
- php and php-fpm (7.2)
- Laravel (php framework - PixelFed is build on it)
- a Redis database
- supervisor (to run horizon as a daemon)

### Additionally this script will install:
- fail2ban (Intrusion Prevention System)
- UFW (simple iptables configuration tool)

## How to use this script
Download -> make it executable -> run script
```
wget https://raw.githubusercontent.com/insxa/pixelfed-install-script/master/pixelfed-install.sh
chmod +x pixelfed-install.sh
./pixelfed-install.sh
```


ToDo:
- Make installation of Let's Encrypt, fail2ban and UFW optional. Till this is done: Just comment out what you wish not to install.
- Ask for phpMyadmin installation
