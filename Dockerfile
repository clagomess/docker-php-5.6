FROM debian:12-slim AS build-base

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && \
    apt install build-essential wget -y

# httpd
FROM build-base AS build-httpd

WORKDIR /srv/httpd-2.4.59

RUN wget https://archive.apache.org/dist/httpd/httpd-2.4.59.tar.gz -O /srv/httpd-2.4.59.tar.gz && \
    tar -xvf /srv/httpd-2.4.59.tar.gz -C /srv/ && \
    rm /srv/httpd-2.4.59.tar.gz

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt install libaprutil1-dev libpcre2-dev -y

RUN ./configure --enable-so --enable-rewrite --prefix /opt/httpd-2.4.59
RUN make -j$(nproc)
RUN make install

RUN rm /opt/httpd-2.4.59/htdocs/index.html

# openssl-1.0.1u
FROM build-base AS build-openssl

WORKDIR /srv/openssl-1.0.1u

RUN wget https://github.com/openssl/openssl/releases/download/OpenSSL_1_0_1u/openssl-1.0.1u.tar.gz -O /srv/openssl.tar.gz && \
    tar -xvf /srv/openssl.tar.gz --one-top-level=openssl-1.0.1u --strip-components=1 -C /srv/ && \
    rm /srv/openssl.tar.gz

RUN ./config --prefix=/opt/openssl-1.0.1u --openssldir=/opt/openssl-1.0.1u/openssl shared

RUN make depend
RUN make -j$(nproc)
RUN make install

# curl 7.52.0
FROM build-base AS build-curl

WORKDIR /srv/curl-7.52.0

RUN wget https://github.com/curl/curl/archive/refs/tags/curl-7_52_0.tar.gz -O /srv/curl.tar.gz && \
    tar -xvf /srv/curl.tar.gz --one-top-level=curl-7.52.0 --strip-components=1 -C /srv/ && \
    rm /srv/curl.tar.gz

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt install autoconf libtool -y

COPY --from=build-openssl /opt/openssl-1.0.1u /opt/openssl-1.0.1u

RUN ./buildconf
RUN ./configure --prefix=/opt/curl-7.52.0 \
    --with-ssl=/opt/openssl-1.0.1u \
    --disable-shared
RUN make -j$(nproc)
RUN make install

# php 5.6.7
FROM build-base AS build-php

WORKDIR /srv/php-5.6.7

RUN wget https://museum.php.net/php5/php-5.6.7.tar.gz -O /srv/php-5.6.7.tar.gz && \
    tar -xvf /srv/php-5.6.7.tar.gz  --one-top-level=php-5.6.7 --strip-components=1 -C /srv/ && \
    rm /srv/php-5.6.7.tar.gz

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt install libltdl-dev libaprutil1-dev libxml2-dev zlib1g-dev libgd-dev libpq-dev libmcrypt-dev -y

RUN ln -s /usr/include/x86_64-linux-gnu/curl /usr/include/curl && \
    ln -s /usr/lib/x86_64-linux-gnu/libjpeg.so /usr/lib/ && \
    ln -s /usr/lib/x86_64-linux-gnu/libpng.so /usr/lib/

COPY --from=build-httpd /opt/httpd-2.4.59 /opt/httpd-2.4.59
COPY --from=build-openssl /opt/openssl-1.0.1u /opt/openssl-1.0.1u
COPY --from=build-curl /opt/curl-7.52.0 /opt/curl-7.52.0

# ./configure --help
RUN ./configure \
    --prefix=/opt/php-5.6.7 \
    --with-config-file-scan-dir=/opt/php-5.6.7/php.ini.d \
    --with-apxs2=/opt/httpd-2.4.59/bin/apxs \
    --with-pgsql \
    --with-pdo-pgsql \
    --with-mysql \
    --with-pdo-mysql \
    --with-gd \
    --with-curl=/opt/curl-7.52.0 \
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

# php xdebug
FROM build-base AS build-xdebug

WORKDIR /srv/xdebug-2.5.5

RUN wget https://github.com/xdebug/xdebug/archive/refs/tags/XDEBUG_2_5_5.tar.gz -O /srv/xdebug-2.5.5.tar.gz && \
    tar -xvf /srv/xdebug-2.5.5.tar.gz --one-top-level=xdebug-2.5.5 --strip-components=1 -C /srv/ && \
    rm /srv/xdebug-2.5.5.tar.gz

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt install autoconf libtool -y

COPY --from=build-php /opt/php-5.6.7 /opt/php-5.6.7

RUN /opt/php-5.6.7/bin/phpize 
RUN ./configure --enable-xdebug --with-php-config=/opt/php-5.6.7/bin/php-config
RUN make -j$(nproc)
RUN make install

RUN cd / && \
    tar -czvf xdebug-result.tar.gz \
    /opt/php-5.6.7/lib/php/extensions/no-debug-zts-20131226/xdebug.so

# release
FROM debian:12-slim AS release

LABEL org.opencontainers.image.source=https://github.com/clagomess/docker-php-5.6
LABEL org.opencontainers.image.description="Functional docker image for legacy PHP 5.6 + HTTPD + XDEBUG"

WORKDIR /srv/htdocs

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && \
    apt install locales libpq5 libgd3 libcurl4 libmcrypt4 libxml2 libpcre2-8-0 libaprutil1 zip -y

RUN locale-gen pt_BR.UTF-8 \
&& echo "locales locales/locales_to_be_generated multiselect pt_BR.UTF-8 UTF-8" | debconf-set-selections \
&& rm /etc/locale.gen \
&& dpkg-reconfigure --frontend noninteractive locales

#TODO: fix
#RUN mkdir -p /opt/opcache && \
#    wget https://raw.githubusercontent.com/rlerdorf/opcache-status/refs/heads/master/opcache.php -O /opt/opcache/index.php

ADD ./soap-includes.tar.gz /opt/php-5.6.7/lib/php
COPY ./init.sh /opt/init.sh
COPY php.ini.d /opt/php-5.6.7/php.ini.d/
COPY httpd.conf.d /opt/httpd-2.4.59/conf.d/

COPY --from=build-openssl /opt/openssl-1.0.1u /opt/openssl-1.0.1u
COPY --from=build-curl /opt/curl-7.52.0 /opt/curl-7.52.0
COPY --from=build-php /opt/httpd-2.4.59 /opt/httpd-2.4.59
COPY --from=build-php /opt/php-5.6.7 /opt/php-5.6.7
COPY --from=build-xdebug /opt/php-5.6.7/lib/php/extensions/no-debug-zts-20131226/xdebug.so /opt/php-5.6.7/lib/php/extensions/no-debug-zts-20131226/xdebug.so

RUN echo 'Include conf.d/*.conf' >> /opt/httpd-2.4.59/conf/httpd.conf

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
