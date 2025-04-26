FROM debian:12-slim AS build-base

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

RUN rm /usr/local/apache2/htdocs/index.html

RUN cd / && tar -czvf httpd-result.tar.gz \
    /usr/local/apache2


# php
FROM build-base AS build-php

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt install libltdl-dev libaprutil1-dev libxml2-dev zlib1g-dev libcurl4-openssl-dev libgd-dev libpq-dev libmcrypt-dev -y

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
RUN cd /srv/php-5.6.9 && \
    ./configure --with-apxs2=/usr/local/apache2/bin/apxs \
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
    --with-zlib

RUN cd /srv/php-5.6.9 && make -j4
RUN cd /srv/php-5.6.9 && make install
RUN cp /srv/php-5.6.9/php.ini-development /usr/local/lib/php.ini

RUN cd / && tar -czvf php-result.tar.gz \
    /usr/local/lib/php \
    /usr/local/include/php \
    /usr/local/apache2/conf/httpd.conf  \
    /usr/local/apache2/conf/httpd.conf.bak \
    /usr/local/apache2/modules/libphp5.so \
    /usr/local/bin/php-config  \
    /usr/local/bin/phpize  \
    /usr/local/bin/peardev \
    /usr/local/bin/pear  \
    /usr/local/bin/pecl  \
    /usr/local/bin/php \
    /usr/local/bin/phar \
    /usr/local/etc/pear.conf \
    /usr/local/lib/php.ini

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
FROM debian:12-slim AS release-base

RUN mkdir /release-root

COPY --from=build-httpd /httpd-result.tar.gz /httpd-result.tar.gz
RUN tar -xvf /httpd-result.tar.gz -C /release-root

COPY --from=build-php /php-result.tar.gz /php-result.tar.gz
RUN tar -xvf /php-result.tar.gz -C /release-root

COPY --from=build-xdebug /xdebug-result.tar.gz /xdebug-result.tar.gz
RUN tar -xvf /xdebug-result.tar.gz -C /release-root

ADD ./soap-includes.tar.gz /release-root/usr/local/lib/php
COPY ./init.sh /release-root/srv/init.sh

# release
FROM debian:12-slim AS release

LABEL org.opencontainers.image.source=https://github.com/clagomess/docker-php-5.6
LABEL org.opencontainers.image.description="Functional docker image for legacy PHP 5.6 + HTTPD + XDEBUG"

WORKDIR /usr/local/apache2/htdocs

ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update \
    && apt install locales libpq5 libgd3 libcurl4 libmcrypt4 libxml2 libpcre2-8-0 libaprutil1 -y

RUN locale-gen pt_BR.UTF-8 \
&& echo "locales locales/locales_to_be_generated multiselect pt_BR.UTF-8 UTF-8" | debconf-set-selections \
&& rm /etc/locale.gen \
&& dpkg-reconfigure --frontend noninteractive locales

COPY --from=release-base /release-root /

# php config
RUN echo '\n\
date.timezone = America/Sao_Paulo\n\
short_open_tag=On\n\
display_errors = On\n\
error_reporting = E_ALL & ~E_DEPRECATED & ~E_NOTICE\n\
log_errors = On\n\
error_log = /var/log/php/error.log\n\
\n\
# XDEBUG\n\
zend_extension=/usr/local/lib/php/extensions/no-debug-zts-20131226/xdebug.so\n\
xdebug.remote_enable=${XDEBUG_REMOTE_ENABLE}\n\
xdebug.remote_handler=dbgp\n\
xdebug.remote_mode=req\n\
xdebug.remote_host=${XDEBUG_REMOTE_HOST}\n\
xdebug.remote_port=${XDEBUG_REMOTE_PORT}\n\
xdebug.remote_autostart=1\n\
xdebug.extended_info=1\n\
xdebug.remote_connect_back = 0\n\
xdebug.remote_log = /var/log/php/xdebug.log\n\
\n\
# OPCACHE\n\
zend_extension=/usr/local/lib/php/extensions/no-debug-zts-20131226/opcache.so\n\
opcache.memory_consumption=128\n\
opcache.interned_strings_buffer=8\n\
opcache.max_accelerated_files=4000\n\
opcache.revalidate_freq=2\n\
opcache.fast_shutdown=1\n\
opcache.enable_cli=1\n\
' >> /usr/local/lib/php.ini \
&& sed -i -- "s/magic_quotes_gpc = On/magic_quotes_gpc = Off/g" /usr/local/lib/php.ini

# config httpd
RUN echo '\n\
LoadModule rewrite_module modules/mod_rewrite.so\n\
ServerName localhost\n\
AddType application/x-httpd-php .php .phtml\n\
User www-data\n\
Group www-data\n\
Alias "/opcache" "/srv/opcache"\n\
<Directory "/srv/opcache">\n\
    Allow from all\n\
</Directory>\n\
' >> /usr/local/apache2/conf/httpd.conf \
&& sed -i -- "s/logs\/error_log/\/var\/log\/apache\/error_log/g" /usr/local/apache2/conf/httpd.conf \
&& sed -i -- "s/logs\/access_log/\/var\/log\/apache\/access_log/g" /usr/local/apache2/conf/httpd.conf \
&& sed -i -- "s/AllowOverride None/AllowOverride All/g" /usr/local/apache2/conf/httpd.conf \
&& sed -i -- "s/AllowOverride None/AllowOverride All/g" /usr/local/apache2/conf/httpd.conf \
&& sed -i -- "s/AllowOverride none/AllowOverride All/g" /usr/local/apache2/conf/httpd.conf \
&& sed -i -- "s/DirectoryIndex index.html/DirectoryIndex index.html index.php/g" /usr/local/apache2/conf/httpd.conf

# create log files
RUN mkdir /var/log/php \
    && mkdir /var/log/apache \
    && touch /var/log/php/error.log \
    && touch /var/log/php/xdebug.log \
    && touch /var/log/apache/access_log \
    && touch /var/log/apache/error_log \
    && chown www-data:www-data /var/log/php/error.log \
    && chown www-data:www-data /var/log/php/xdebug.log \
    && chown www-data:www-data /var/log/apache/access_log \
    && chown www-data:www-data /var/log/apache/error_log

# entrypoint
CMD ["bash", "/srv/init.sh"]
