FROM debian:10-slim AS build-base

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update  \
    && apt install build-essential wget -y

# httpd
FROM build-base AS build-httpd

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt install libaprutil1-dev libpcre2-dev -y

RUN wget https://archive.apache.org/dist/httpd/httpd-2.4.59.tar.gz -O /srv/httpd-2.4.59.tar.gz && \
    tar -xvf /srv/httpd-2.4.59.tar.gz -C /srv/ && \
    rm /srv/httpd-2.4.59.tar.gz

RUN cd /srv/httpd-2.4.59 \
    && ./configure --enable-so --enable-rewrite \
    && make -j4 \
    && make install

RUN cd / && tar -czvf httpd-result.tar.gz \
    /usr/local/apache2


# php
FROM build-base AS build-php

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt install libaprutil1-dev libxml2-dev zlib1g-dev libcurl4-openssl-dev libgd-dev libpq-dev libmcrypt-dev -y

COPY --from=build-httpd /httpd-result.tar.gz /httpd-result.tar.gz

RUN cd / \
    && tar -xvf httpd-result.tar.gz \
    && ldconfig

RUN wget https://museum.php.net/php5/php-5.6.9.tar.gz -O /srv/php-5.6.9.tar.gz && \
    tar -xvf /srv/php-5.6.9.tar.gz -C /srv/ && \
    rm /srv/php-5.6.9.tar.gz

RUN ln -s /usr/include/x86_64-linux-gnu/curl /usr/include/curl && \
    ln -s /usr/lib/x86_64-linux-gnu/libjpeg.so /usr/lib/ && \
    ln -s /usr/lib/x86_64-linux-gnu/libpng.so /usr/lib/

# ./configure --help
RUN cd /srv/php-5.6.9 \
&& ./configure --with-apxs2=/usr/local/apache2/bin/apxs \
    --with-pgsql \
    --with-pdo-pgsql \
    --with-mysql \
    --with-pdo-mysql \
    --with-gd \
    --with-curl=/usr \
    --enable-soap \
    --with-mcrypt \
    --enable-mbstring \
    --enable-calendar \
    --enable-bcmath \
    --enable-zip \
    --enable-exif \
    --enable-ftp \
    --enable-shmop \
    --enable-sockets \
    --enable-sysvmsg \
    --enable-sysvsem \
    --enable-sysvshm \
    --enable-wddx \
    --enable-dba \
    --with-gettext \
    --with-ttf \
    --with-png-dir=/usr \
    --with-jpeg-dir=/usr \
    #--with-freetype-dir=/usr \
    --with-zlib \
    && make -j4 \
    && make install

RUN cp /srv/php-5.6.9/php.ini-development /usr/local/lib/php.ini

# php xdebug
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt install autoconf -y

FROM build-php AS build-xdebug

RUN wget https://github.com/xdebug/xdebug/archive/refs/tags/XDEBUG_2_5_5.tar.gz -O /srv/xdebug-2.5.5.tar.gz && \
    tar -xvf /srv/xdebug-2.5.5.tar.gz -C /srv/ && \
    rm /srv/xdebug-2.5.5.tar.gz

RUN cd /srv/xdebug-XDEBUG_2_5_5 \
    && phpize \
    && ./configure --enable-xdebug \
    && make -j4 \
    && make install

RUN cd / && \
    tar -czvf xdebug-result.tar.gz \
    /usr/local/lib/php/extensions/no-debug-zts-20131226/xdebug.so

# release base
FROM debian:10-slim AS release-base

RUN mkdir /release-root

COPY --from=build-httpd /httpd-result.tar.gz /httpd-result.tar.gz
RUN tar -xvf /httpd-result.tar.gz -C /release-root

COPY --from=build-php /php-result.tar.gz /php-result.tar.gz
RUN tar -xvf /php-result.tar.gz -C /release-root

COPY --from=build-xdebug /xdebug-result.tar.gz /xdebug-result.tar.gz
RUN tar -xvf /xdebug-result.tar.gz -C /release-root

# release
FROM debian:10-slim AS release

LABEL org.opencontainers.image.source=https://github.com/clagomess/docker-php-5.6
LABEL org.opencontainers.image.description="Functional docker image for legacy PHP 5.6 + HTTPD + XDEBUG"

ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update \
    && apt install locales libpq5 libgd3 libcurl4 libmcrypt4 -y

RUN locale-gen pt_BR.UTF-8 \
&& echo "locales locales/locales_to_be_generated multiselect pt_BR.UTF-8 UTF-8" | debconf-set-selections \
&& rm /etc/locale.gen \
&& dpkg-reconfigure --frontend noninteractive locales

COPY --from=release-base /release-root /



#RUN apt update
#RUN apt install build-essential -y
#
####
#RUN apt install vim wget -y
#RUN apt-get install -y apt-transport-https lsb-release ca-certificates
#RUN wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
#RUN echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
#RUN apt update
#RUN apt upgrade -y
#RUN apt install apache2 -y
#
## php-pear php5.6-dev
#RUN apt install php5.6 php5.6-mbstring php5.6-soap php-xdebug php5.6-sybase  -y
#
## php xdebug
#RUN echo "xdebug.remote_enable=1" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
#&& echo "xdebug.remote_handler=dbgp" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
#&& echo "xdebug.remote_mode=req" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
#&& echo "xdebug.remote_host=host.docker.internal" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
#&& echo "xdebug.remote_port=9000" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
#&& echo "xdebug.remote_autostart=1" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
#&& echo "xdebug.extended_info=1" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini \
#&& echo "xdebug.remote_connect_back = 0" >> /etc/php/5.6/apache2/conf.d/20-xdebug.ini
#
## config httpd
#RUN sed -i -- "s/AllowOverride None/AllowOverride All/g" /etc/apache2/apache2.conf \
#&& sed -i -- "s/AllowOverride none/AllowOverride All/g" /etc/apache2/apache2.conf
#
## config php
#RUN echo "date.timezone = America/Sao_Paulo" > /etc/php/5.6/apache2/conf.d/sistemas.ini \
#&& echo "short_open_tag=On" >> /etc/php/5.6/apache2/conf.d/sistemas.ini \
#&& echo "display_errors = On" >> /etc/php/5.6/apache2/conf.d/sistemas.ini \
#&& echo "error_reporting = E_ALL & ~E_DEPRECATED & ~E_NOTICE" >> /etc/php/5.6/apache2/conf.d/sistemas.ini
#
## vhost
#RUN a2enmod actions && a2enmod alias
#RUN echo "Alias /logs /var/www/html/.idea" > /etc/apache2/sites-available/sistemas.conf \
#&& echo "<Directory /var/www/html/.idea>" >> /etc/apache2/sites-available/sistemas.conf \
#&& echo "Allow from all" >> /etc/apache2/sites-available/sistemas.conf \
#&& echo "</Directory>" >> /etc/apache2/sites-available/sistemas.conf
#RUN a2ensite sistemas
#
## config log
#RUN ln -sf /dev/stdout /var/log/apache2/access.log \
#&& ln -sf /dev/stderr /var/log/apache2/error.log
