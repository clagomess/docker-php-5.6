FROM debian:8

RUN apt update
RUN apt install build-essential -y

###
RUN apt install vim wget -y
RUN apt-get install -y apt-transport-https lsb-release ca-certificates
RUN wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
RUN echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
RUN apt update
RUN apt upgrade -y
RUN apt install apache2 -y

# php-pear php5.6-dev
RUN apt install php5.6 php5.6-mbstring php5.6-soap php-xdebug php5.6-sybase  -y

# php xdebug
RUN echo "xdebug.remote_enable=1" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
&& echo "xdebug.remote_handler=dbgp" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
&& echo "xdebug.remote_mode=req" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
&& echo "xdebug.remote_host=host.docker.internal" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
&& echo "xdebug.remote_port=9000" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
&& echo "xdebug.remote_autostart=1" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
&& echo "xdebug.extended_info=1" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
&& echo "xdebug.remote_connect_back = 0" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini

# config httpd
RUN sed -i -- "s/AllowOverride None/AllowOverride All/g" /etc/apache2/apache2.conf \
&& sed -i -- "s/AllowOverride none/AllowOverride All/g" /etc/apache2/apache2.conf

# config php
RUN echo "date.timezone = America/Sao_Paulo" > /etc/php/5.6/apache2/conf.d/sistemas.ini \
&& echo "short_open_tag=On" >> /etc/php/5.6/apache2/conf.d/sistemas.ini \
&& echo "display_errors = On" >> /etc/php/5.6/apache2/conf.d/sistemas.ini \
&& echo "error_reporting = E_ALL & ~E_DEPRECATED & ~E_NOTICE" >> /etc/php/5.6/apache2/conf.d/sistemas.ini

# vhost
RUN a2enmod actions && a2enmod alias
RUN echo "Alias /logs /var/www/html/.idea" > /etc/apache2/sites-available/sistemas.conf \
&& echo "<Directory /var/www/html/.idea>" >> /etc/apache2/sites-available/sistemas.conf \
&& echo "Allow from all" >> /etc/apache2/sites-available/sistemas.conf \
&& echo "</Directory>" >> /etc/apache2/sites-available/sistemas.conf
RUN a2ensite sistemas

# config log
RUN ln -sf /dev/stdout /var/log/apache2/access.log \
&& ln -sf /dev/stderr /var/log/apache2/error.log