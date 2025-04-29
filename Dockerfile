FROM debian:12-slim AS build-base

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && \
    apt install build-essential wget -y

# httpd
FROM build-base AS build-httpd

RUN wget https://archive.apache.org/dist/httpd/httpd-2.4.59.tar.gz -O /srv/httpd-2.4.59.tar.gz && \
    tar -xvf /srv/httpd-2.4.59.tar.gz -C /srv/ && \
    rm /srv/httpd-2.4.59.tar.gz

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt install libaprutil1-dev libpcre2-dev -y

WORKDIR /srv/httpd-2.4.59 

RUN ./configure --enable-so --enable-rewrite --prefix /opt/httpd-2.4.59
RUN make -j$(nproc)
RUN make install

RUN rm /opt/httpd-2.4.59/htdocs/index.html

RUN cd / && \
    tar -czvf httpd-result.tar.gz /opt/httpd-2.4.59

# openssl-1.0.1u
FROM build-base AS build-openssl

RUN wget https://github.com/openssl/openssl/releases/download/OpenSSL_1_0_1u/openssl-1.0.1u.tar.gz -O /srv/openssl.tar.gz && \
    tar -xvf /srv/openssl.tar.gz --one-top-level=openssl-1.0.1u --strip-components=1 -C /srv/ && \
    rm /srv/openssl.tar.gz

WORKDIR /srv/openssl-1.0.1u

RUN ./config --prefix=/opt/openssl-1.0.1u --openssldir=/opt/openssl-1.0.1u/openssl shared

RUN make depend
RUN make -j$(nproc)
RUN make install

RUN cd / && \
    tar -czvf openssl-result.tar.gz /opt/openssl-1.0.1u

# php
FROM build-base AS build-php

RUN wget https://museum.php.net/php5/php-5.6.7.tar.gz -O /srv/php-5.6.7.tar.gz && \
    tar -xvf /srv/php-5.6.7.tar.gz  --one-top-level=php-5.6.7 --strip-components=1 -C /srv/ && \
    rm /srv/php-5.6.7.tar.gz

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt install libltdl-dev libaprutil1-dev libxml2-dev zlib1g-dev libgd-dev libpq-dev libmcrypt-dev -y

COPY --from=build-httpd /httpd-result.tar.gz /httpd-result.tar.gz
COPY --from=build-openssl /openssl-result.tar.gz /openssl-result.tar.gz

RUN cd / && \
    tar -xvf httpd-result.tar.gz && \
    tar -xvf openssl-result.tar.gz

RUN ln -s /usr/include/x86_64-linux-gnu/curl /usr/include/curl && \
    ln -s /usr/lib/x86_64-linux-gnu/libjpeg.so /usr/lib/ && \
    ln -s /usr/lib/x86_64-linux-gnu/libpng.so /usr/lib/

WORKDIR /srv/php-5.6.7

# ./configure --help
RUN ./configure --prefix=/opt/php-5.6.7 \
    --with-apxs2=/opt/httpd-2.4.59/bin/apxs \
    --with-pgsql \
    --with-pdo-pgsql \
    --with-mysql \
    --with-pdo-mysql \
    --with-gd \
    #--with-curl=/usr \
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
    --with-openssl=/opt/openssl-1.0.1u

RUN make -j$(nproc)
RUN make install
RUN cp /srv/php-5.6.7/php.ini-development /opt/php-5.6.7/lib/php.ini

RUN cd / && \
    tar -czvf php-result.tar.gz /opt/php-5.6.7

RUN cd / && \
    tar -czvf httpd-result.tar.gz /opt/httpd-2.4.59

# php xdebug
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && \
    apt install autoconf -y

FROM build-php AS build-xdebug

RUN wget https://github.com/xdebug/xdebug/archive/refs/tags/XDEBUG_2_5_5.tar.gz -O /srv/xdebug-2.5.5.tar.gz && \
    tar -xvf /srv/xdebug-2.5.5.tar.gz --one-top-level=xdebug-2.5.5 --strip-components=1 -C /srv/ && \
    rm /srv/xdebug-2.5.5.tar.gz

WORKDIR /srv/xdebug-2.5.5

RUN /opt/php-5.6.7/bin/phpize 
RUN ./configure --enable-xdebug --with-php-config=/opt/php-5.6.7/bin/php-config
RUN make -j$(nproc)
RUN make install

RUN cd / && \
    tar -czvf xdebug-result.tar.gz \
    /opt/php-5.6.7/lib/php/extensions/no-debug-zts-20131226/xdebug.so

# release base
FROM debian:12-slim AS release-base

RUN mkdir /release-root

COPY --from=build-openssl /openssl-result.tar.gz /openssl-result.tar.gz
RUN tar -xvf /openssl-result.tar.gz -C /release-root

COPY --from=build-php /httpd-result.tar.gz /httpd-result.tar.gz
RUN tar -xvf /httpd-result.tar.gz -C /release-root

COPY --from=build-php /php-result.tar.gz /php-result.tar.gz
RUN tar -xvf /php-result.tar.gz -C /release-root

COPY --from=build-xdebug /xdebug-result.tar.gz /xdebug-result.tar.gz
RUN tar -xvf /xdebug-result.tar.gz -C /release-root

ADD ./soap-includes.tar.gz /release-root/opt/php-5.6.7/lib/php
COPY ./init.sh /release-root/opt/init.sh

# release
FROM debian:12-slim AS release

LABEL org.opencontainers.image.source=https://github.com/clagomess/docker-php-5.6
LABEL org.opencontainers.image.description="Functional docker image for legacy PHP 5.6 + HTTPD + XDEBUG"

WORKDIR /opt/httpd-2.4.59/htdocs

ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && \
    apt install locales libpq5 libgd3 libcurl4 libmcrypt4 libxml2 libpcre2-8-0 libaprutil1 zip -y

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
zend_extension=/opt/php-5.6.7/lib/php/extensions/no-debug-zts-20131226/xdebug.so\n\
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
zend_extension=/opt/php-5.6.7/lib/php/extensions/no-debug-zts-20131226/opcache.so\n\
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
' >> /opt/httpd-2.4.59/conf/httpd.conf \
&& sed -i -- "s/logs\/error_log/\/var\/log\/apache\/error_log/g" /opt/httpd-2.4.59/conf/httpd.conf \
&& sed -i -- "s/logs\/access_log/\/var\/log\/apache\/access_log/g" /opt/httpd-2.4.59/conf/httpd.conf \
&& sed -i -- "s/AllowOverride None/AllowOverride All/g" /opt/httpd-2.4.59/conf/httpd.conf \
&& sed -i -- "s/AllowOverride None/AllowOverride All/g" /opt/httpd-2.4.59/conf/httpd.conf \
&& sed -i -- "s/AllowOverride none/AllowOverride All/g" /opt/httpd-2.4.59/conf/httpd.conf \
&& sed -i -- "s/DirectoryIndex index.html/DirectoryIndex index.html index.php/g" /opt/httpd-2.4.59/conf/httpd.conf

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
CMD ["bash", "/opt/init.sh"]
