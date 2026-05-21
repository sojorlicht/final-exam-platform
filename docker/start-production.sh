#!/bin/sh
set -e

PORT="${PORT:-8080}"

# Also listen on $PORT when Railway uses a non-standard port
if [ "$PORT" != "80" ] && [ "$PORT" != "8080" ]; then
  echo "Adding listen on 0.0.0.0:${PORT}"
  sed -i "/listen 8080;/a\    listen 0.0.0.0:${PORT};" /etc/nginx/http.d/default.conf
fi

echo "Nginx listening on ports 80, 8080${PORT:+ and ${PORT}}"

nginx -t

php-fpm -D
exec nginx -g 'daemon off;'
