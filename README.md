# docker-php-5.6

DON'T USE IN PRODUCTION!

## Download
- Github: `docker pull ghcr.io/clagomess/docker-php-5.6:latest`
- DockerHub: `docker pull clagomess/docker-php-5.6:latest`

## Use
- DocumentRoot: `/srv/htdocs/`
- Custom PHP Config: `/opt/php-5.6.7/php.ini.d/`
- Custom Apache HTTPD Config: `/opt/httpd-2.4.59/conf.d/`
- OpCache Panel: `http://localhost:8000/opcache/`

Example:
```bash
docker run --rm \
  -p 8000:80 \
  -e XDEBUG_REMOTE_ENABLE=1 \
  -e XDEBUG_REMOTE_HOST=host.docker.internal \
  -e XDEBUG_REMOTE_PORT=9000 \
  -v .:/srv/htdocs \
  clagomess/docker-php-5.6
```
