#
#                    ##        .
#              ## ## ##       ==
#           ## ## ## ##      ===
#       /""""""""""""""""\___/ ===
#  ~~~ {~~ ~~~~ ~~~ ~~~~ ~~ ~ /  ===- ~~~
#       \______ o          __/
#         \    \        __/
#          \____\______/
#
#          |          |
#       __ |  __   __ | _  __   _
#      /  \| /  \ /   |/  / _\ |
#      \__/| \__/ \__ |\_ \__  |
#
# Dockerfile for ISPConfig with MariaDB database
#
# https://www.howtoforge.com/tutorial/perfect-server-debian-9-stretch-apache-bind-dovecot-ispconfig-3-1/
#
FROM debian:stretch-slim

LABEL maintainer="jon.crooke@gmail.com"
LABEL description="ISPConfig 3.1 on Debian Stretch, with Roundcube mail, phpMyAdmin and more"

# All arguments
ARG BUILD_CERTBOT="yes"
ARG BUILD_HOSTNAME="myhost.test.com"
ARG BUILD_ISPCONFIG="3-stable"
ARG BUILD_ISPCONFIG_PORT="8080"
ARG BUILD_MYSQL_PW="pass"
ARG BUILD_PHPMYADMIN_PW="phpmyadmin"
ARG BUILD_PRINTING="no"
ARG BUILD_ROUNDCUBE_CONFIG="/etc/roundcube"
ARG BUILD_ROUNDCUBE_DIR="/etc/roundcube"
ARG BUILD_ROUNDCUBE_PW="secretpassword"
ARG BUILD_TZ="Europe/Berlin"

# Let the container know that there is no tty
ENV DEBIAN_FRONTEND noninteractive

# --- set timezone
RUN ln -fs /usr/share/zoneinfo/${BUILD_TZ} /etc/localtime; \
    dpkg-reconfigure -f noninteractive tzdata

# --- 1 Preliminary
RUN apt-get -y update && apt-get -y upgrade && apt-get -y install rsyslog rsyslog-relp logrotate supervisor git sendemail rsnapshot heirloom-mailx
RUN touch /var/log/cron.log
# Create the log file to be able to run tail
RUN touch /var/log/auth.log

# --- 2 Install the SSH server
RUN apt-get -y install ssh openssh-server rsync

# --- 3 Install a shell text editor
RUN apt-get -y install nano vim-nox

# --- 5 Update Your Debian Installation
ADD ./build/etc/apt/sources.list /etc/apt/sources.list
RUN apt-get -y update && apt-get -y upgrade

# --- 6 Change The Default Shell
RUN echo "dash  dash/sh boolean no" | debconf-set-selections
RUN dpkg-reconfigure dash

# --- 7 Synchronize the System Clock
RUN apt-get -y install ntp ntpdate

# --- 8 Install Postfix, Dovecot, MySQL, phpMyAdmin, rkhunter, binutils
RUN echo "mysql-server mysql-server/root_password password ${BUILD_MYSQL_PW}"           | debconf-set-selections
RUN echo "mysql-server mysql-server/root_password_again password ${BUILD_MYSQL_PW}"     | debconf-set-selections
RUN echo "mariadb-server mariadb-server/root_password password ${BUILD_MYSQL_PW}"       | debconf-set-selections
RUN echo "mariadb-server mariadb-server/root_password_again password ${BUILD_MYSQL_PW}" | debconf-set-selections
RUN apt-get -y install postfix postfix-mysql postfix-doc mariadb-client mariadb-server openssl getmail4 rkhunter binutils dovecot-imapd dovecot-pop3d dovecot-mysql dovecot-sieve dovecot-lmtpd sudo
ADD ./build/etc/postfix/master.cf /etc/postfix/master.cf
ADD ./build/etc/mysql/debian.cnf /etc/mysql
ADD ./build/etc/mysql/50-server.cnf /etc/mysql/mariadb.conf.d/
RUN sed -i "s|password =|password = ${BUILD_MYSQL_PW}|" /etc/mysql/debian.cnf
RUN echo "mysql soft nofile 65535\nmysql hard nofile 65535\n" >> /etc/security/limits.conf
RUN mkdir -p /etc/systemd/system/mysql.service.d/; echo "[Service]\nLimitNOFILE=infinity\n" >> /etc/systemd/system/mysql.service.d/limits.conf
RUN service mysql restart; echo "UPDATE mysql.user SET plugin = 'mysql_native_password', Password = PASSWORD('${BUILD_MYSQL_PW}') WHERE User = 'root';" | mysql -u root -p${BUILD_MYSQL_PW}

RUN service postfix restart
RUN service mysql restart

# --- 9 Install Amavisd-new, SpamAssassin And Clamav
RUN apt-get -y install amavisd-new spamassassin clamav clamav-daemon zoo unzip bzip2 arj nomarch lzop cabextract apt-listchanges libnet-ldap-perl libauthen-sasl-perl clamav-docs daemon libio-string-perl libio-socket-ssl-perl libnet-ident-perl zip libnet-dns-perl libdbd-mysql-perl postgrey
ADD ./build/etc/clamav/clamd.conf /etc/clamav/clamd.conf
RUN freshclam
RUN service spamassassin stop
RUN systemctl disable spamassassin

# --- 10 Install Apache2, PHP5, phpMyAdmin, FCGI, suExec, Pear, And mcrypt
RUN echo 'phpmyadmin phpmyadmin/dbconfig-install boolean true' | debconf-set-selections
RUN echo "phpmyadmin phpmyadmin/mysql/admin-pass password ${BUILD_MYSQL_PW}" | debconf-set-selections
RUN echo 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2' | debconf-set-selections
RUN service mysql restart && apt-get -y install apache2 apache2-doc apache2-utils libapache2-mod-php php7.0 php7.0-common php7.0-gd php7.0-mysql php7.0-imap phpmyadmin php7.0-cli php7.0-cgi libapache2-mod-fcgid apache2-suexec-pristine php-pear php7.0-mcrypt mcrypt  imagemagick libruby libapache2-mod-python php7.0-curl php7.0-intl php7.0-pspell php7.0-recode php7.0-sqlite3 php7.0-tidy php7.0-xmlrpc php7.0-xsl memcached php-memcache php-imagick php-gettext php7.0-zip php7.0-mbstring memcached libapache2-mod-passenger php7.0-soap
RUN a2enmod suexec rewrite ssl actions include dav_fs dav auth_digest cgi headers
ADD ./build/etc/apache2/httpoxy.conf /etc/apache2/conf-available/
RUN echo "ServerName ${BUILD_HOSTNAME}" | tee /etc/apache2/conf-available/fqdn.conf && a2enconf fqdn
# TODO change phpmyadmin password with debconf?
RUN service mysql restart; mysql -uroot -p${BUILD_MYSQL_PW} -e "SET PASSWORD FOR 'phpmyadmin'@'localhost' = PASSWORD('${BUILD_PHPMYADMIN_PW}');"
ADD ./build/etc/phpmyadmin/config.inc.php /var/lib/phpmyadmin
RUN sed -i "s|<control-pass>|${BUILD_PHPMYADMIN_PW}|" /var/lib/phpmyadmin/config.inc.php
RUN sed -i "s|\$dbpass='.*';|\$dbpass='${BUILD_PHPMYADMIN_PW}';|" /etc/phpmyadmin/config-db.php
RUN a2enconf httpoxy && service apache2 restart

# --- 11 Free SSL RUN mkdir /opt/certbot
RUN if [ "${BUILD_CERTBOT}" = "yes" ]; then apt-get -y install certbot; fi

# --- 12 PHP-FPM
RUN apt-get -y install php7.0-fpm
RUN a2enmod actions proxy_fcgi alias; service apache2 restart
# --- 12.2 Opcode Cache
RUN apt-get -y install php7.0-opcache php-apcu; service apache2 restart

# --- 13 Install Mailman
# Doesn't really work (yet)
RUN echo 'mailman mailman/default_server_language select en' | debconf-set-selections
RUN apt-get -y install mailman
# RUN ["/usr/lib/mailman/bin/newlist", "-q", "mailman", "mail@mail.com", "pass"]
ADD ./build/etc/aliases /etc/aliases
RUN newaliases
RUN service postfix restart
RUN ln -s /etc/mailman/apache.conf /etc/apache2/conf-enabled/mailman.conf

# --- 14 Install PureFTPd And Quota
# install package building helpers
RUN apt-get -y install pure-ftpd-common pure-ftpd-mysql quota quotatool
RUN groupadd ftpgroup
RUN useradd -g ftpgroup -d /dev/null -s /etc ftpuser
ADD ./build/etc/default/pure-ftpd-common /etc/default/pure-ftpd-common

# --- 15 Install BIND DNS Server, haveged
RUN apt-get -y install bind9 dnsutils haveged

# --- 16 Install Vlogger, Webalizer, And AWStats
RUN apt-get -y install webalizer awstats geoip-database libclass-dbi-mysql-perl libtimedate-perl
ADD ./build/etc/cron.d/awstats /etc/cron.d/

# --- 17 Install Jailkit
RUN apt-get -y install build-essential autoconf automake libtool flex bison debhelper binutils
RUN cd /tmp; wget http://olivier.sessink.nl/jailkit/jailkit-2.19.tar.gz; tar xvfz jailkit-2.19.tar.gz; cd jailkit-2.19; echo 5 > debian/compat; ./debian/rules binary; cd ..; dpkg -i jailkit_2.19-1_*.deb; rm -rf jailkit-2.19*

# --- 18 Install fail2ban
RUN apt-get -y install fail2ban
ADD ./build/etc/fail2ban/jail.local /etc/fail2ban/jail.local
ADD ./build/etc/fail2ban/filter.d/pureftpd.conf /etc/fail2ban/filter.d/pureftpd.conf
ADD ./build/etc/fail2ban/filter.d/dovecot-pop3imap.conf /etc/fail2ban/filter.d/dovecot-pop3imap.conf
RUN echo "ignoreregex =" >> /etc/fail2ban/filter.d/postfix-sasl.conf
RUN service fail2ban restart

# --- 19 Install squirrelmail
#RUN apt-get -y install squirrelmail
#ADD ./build/etc/apache2/conf-enabled/squirrelmail.conf /etc/apache2/conf-enabled/squirrelmail.conf
#ADD ./build/etc/squirrelmail/config.php /etc/squirrelmail/config.php
#RUN chown root:www-data /etc/squirrelmail/config.php && chmod g+r /etc/squirrelmail/config.php
#RUN mkdir /var/lib/squirrelmail/tmp
#RUN chown www-data /var/lib/squirrelmail/tmp
#RUN service mysql restart

# --- 19 Install roundcube
RUN echo "roundcube-core roundcube/dbconfig-install boolean true" | debconf-set-selections
RUN echo "roundcube-core roundcube/database-type select mysql" | debconf-set-selections
RUN echo "roundcube-core roundcube/mysql/admin-pass password ${BUILD_MYSQL_PW}" | debconf-set-selections
RUN service mysql restart; apt-get -y install roundcube roundcube-core roundcube-mysql roundcube-plugins
#RUN sed -i "s/mysql:\/\/roundcube:pass@localhost\/roundcubemail/mysql:\/\/roundcube:${BUILD_ROUNDCUBE_PW}@localhost\/roundcubemail/" ${BUILD_ROUNDCUBE_CONFIG}/config.inc.php
RUN sed -i "s|\$config\['default_host'\] = '';|\$config\['default_host'\] = 'localhost';|" ${BUILD_ROUNDCUBE_CONFIG}/config.inc.php
RUN sed -i "s|\$config\['smtp_server'\] = '';|\$config\['smtp_server'\] = 'localhost';|" ${BUILD_ROUNDCUBE_CONFIG}/config.inc.php
ADD ./build/etc/apache2/roundcube.conf /etc/apache2/conf-enabled/roundcube.conf
RUN service apache2 restart
RUN service mysql restart

# --- 19 Install ispconfig plugins for roundcube
RUN git clone https://github.com/w2c/ispconfig3_roundcube.git /tmp/ispconfig3_roundcube/ && mv /tmp/ispconfig3_roundcube/ispconfig3_* ${BUILD_ROUNDCUBE_DIR}/plugins && rm -Rvf /tmp/ispconfig3_roundcube
RUN echo "\$rcmail_config['plugins'] = array(\"jqueryui\", \"ispconfig3_account\", \"ispconfig3_autoreply\", \"ispconfig3_pass\", \"ispconfig3_spam\", \"ispconfig3_fetchmail\", \"ispconfig3_filter\");" >> ${BUILD_ROUNDCUBE_DIR}/config.inc.php
RUN cd ${BUILD_ROUNDCUBE_DIR}/plugins && mv ispconfig3_account/config/config.inc.php.dist ispconfig3_account/config/config.inc.php

# --- 20 Install ISPConfig 3
RUN cd /tmp && cd . && wget https://ispconfig.org/downloads/ISPConfig-${BUILD_ISPCONFIG}.tar.gz
RUN cd /tmp && tar xfz ISPConfig-${BUILD_ISPCONFIG}.tar.gz
ADD ./build/autoinstall.ini /tmp/ispconfig3_install/install/autoinstall.ini
RUN sed -i "s/^hostname=server1.example.com$/hostname=${BUILD_HOSTNAME}/g"                         /tmp/ispconfig3_install/install/autoinstall.ini
RUN sed -i "s/^ispconfig_port=8080$/ispconfig_port=${BUILD_ISPCONFIG_PORT}/g"                      /tmp/ispconfig3_install/install/autoinstall.ini
RUN sed -i "s/^ssl_cert_common_name=server1.example.com$/ssl_cert_common_name=${BUILD_HOSTNAME}/g" /tmp/ispconfig3_install/install/autoinstall.ini

RUN service mysql restart && php -q /tmp/ispconfig3_install/install/install.php      --autoinstall=/tmp/ispconfig3_install/install/autoinstall.ini
RUN sed -i "s|NameVirtualHost|#NameVirtualHost|" /etc/apache2/sites-enabled/000-ispconfig.conf
RUN sed -i "s|NameVirtualHost|#NameVirtualHost|" /etc/apache2/sites-enabled/000-ispconfig.vhost
################################################################################################
# the key and cert for pure-ftpd should be available :
RUN mkdir -p /etc/ssl/private/
RUN cd /usr/local/ispconfig/interface/ssl ; cat ispserver.key ispserver.crt > ispserver.pem
RUN cd /etc/ssl/private ; ln -sf /usr/local/ispconfig/interface/ssl/ispserver.pem pure-ftpd.pem
RUN echo 1 > /etc/pure-ftpd/conf/TLS

# --- 23 Install printing stuff
RUN if [ "$BUILD_PRINTING" = "yes" ] ; then  apt-get -y install --fix-missing  -y libdmtx-utils dblatex latex-make cups-client lpr ; fi ;

#
# docker-extensions
#
RUN mkdir -p /usr/local/bin
COPY ./build/bin/*             /usr/local/bin/
RUN chmod a+x /usr/local/bin/*

#
# establish supervisord
#
ADD ./build/supervisor /etc/supervisor
# link old /etc/init.d/ startup scripts to supervisor
RUN ls -m1    /etc/supervisor/services.d | while read i; do mv /etc/init.d/$i /etc/init.d/$i-orig ;  ln -sf /etc/supervisor/super-init.sh /etc/init.d/$i ; done
RUN ln -sf    /etc/supervisor/systemctl /bin/systemctl
RUN chmod a+x /etc/supervisor/* /etc/supervisor/*.d/*
COPY ./build/supervisor/invoke-rc.d /usr/sbin/invoke-rc.d
#
# create directory for service volume
#
RUN mkdir -p /service ; chmod a+rwx /service
ADD ./build/track.gitignore /.gitignore

#
# Create bootstrap archives
#
RUN cp -v /etc/passwd /etc/passwd.bootstrap
RUN cp -v /etc/shadow /etc/shadow.bootstrap
RUN cp -v /etc/group  /etc/group.bootstrap
RUN mkdir -p /bootstrap ;  tar -C /var/vmail -czf /bootstrap/vmail.tgz .
RUN mkdir -p /bootstrap ;  tar -C /var/www   -czf /bootstrap/www.tgz  .
ENV TERM xterm

RUN echo "export TERM=xterm" >> /root/.bashrc

EXPOSE 20 21 22 53/udp 53/tcp 80 443 953 8080 30000 30001 30002 30003 30004 30005 30006 30007 30008 30009 3306

#
# startup script
#
ADD ./build/start.sh /start.sh
RUN chmod 755 /start.sh
CMD ["/start.sh"]
