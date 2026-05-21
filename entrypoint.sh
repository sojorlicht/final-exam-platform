#!/bin/sh
set -e

cd /var/www/html

# Railway MySQL variable names (MYSQLHOST) and docker-compose names (MYSQL_HOST)
MYSQL_HOST="${MYSQL_HOST:-${MYSQLHOST:-}}"
MYSQL_PORT="${MYSQL_PORT:-${MYSQLPORT:-3307}}"
MYSQL_USER="${MYSQL_USER:-${MYSQLUSER:-}}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-${MYSQLPASSWORD:-}}"
MYSQL_DATABASE="${MYSQL_DATABASE:-${MYSQLDATABASE:-}}"
export MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE

if [ -n "$MYSQL_HOST" ]; then
  echo "Waiting for MySQL at ${MYSQL_HOST}..."
  attempts=0
  max_attempts=60
  until php -r "
    try {
      new PDO(
        'mysql:host=${MYSQL_HOST};port=${MYSQL_PORT};dbname=${MYSQL_DATABASE}',
        '${MYSQL_USER}',
        '${MYSQL_PASSWORD}'
      );
      exit(0);
    } catch (Exception \$e) {
      exit(1);
    }
  " 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
      echo "MySQL not ready after ${max_attempts} attempts, continuing anyway..."
      break
    fi
    sleep 2
  done
  if [ "$attempts" -lt "$max_attempts" ]; then
    echo "MySQL is ready."
  fi
fi

if [ ! -d vendor ] || [ ! -f vendor/autoload.php ]; then
  composer install --prefer-dist --no-progress --no-interaction --no-dev
fi

php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration

if [ "$APP_ENV" = "prod" ]; then
  php bin/console cache:clear --no-warmup
  php bin/console cache:warmup
  php bin/console asset-map:compile --no-interaction 2>/dev/null || true
fi

# PHP-FPM runs as www-data; cache warmup runs as root
mkdir -p var/cache var/log var/share
chown -R www-data:www-data var

exec "$@"
