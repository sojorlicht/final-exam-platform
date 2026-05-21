# syntax=docker/dockerfile:1

FROM composer:2 AS vendor

WORKDIR /app

COPY composer.json composer.lock symfony.lock ./

RUN composer install \
    --no-dev \
    --no-scripts \
    --no-autoloader \
    --prefer-dist \
    --no-progress

COPY . .

RUN composer install \
    --no-dev \
    --optimize-autoloader \
    --no-scripts \
    --no-progress

# ---------------------------------------------------------------------------
# PHP-FPM base (used by docker-compose "php" service)
# ---------------------------------------------------------------------------
FROM php:8.3-fpm-alpine AS base

RUN apk add --no-cache \
    icu-dev \
    icu-libs \
    libzip-dev \
    libzip \
    oniguruma-dev \
    && docker-php-ext-configure intl \
    && docker-php-ext-install -j"$(nproc)" intl opcache pdo_mysql zip \
    && apk del --no-cache icu-dev libzip-dev oniguruma-dev

# Allow Nginx (separate container) to reach PHP-FPM
RUN sed -i 's/listen = 127.0.0.1:9000/listen = 0.0.0.0:9000/' /usr/local/etc/php-fpm.d/www.conf

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY --from=vendor /app /var/www/html

COPY entrypoint.sh /usr/local/bin/docker-entrypoint
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint \
    && chmod +x /usr/local/bin/docker-entrypoint

RUN mkdir -p var/cache var/log \
    && chown -R www-data:www-data var

ENTRYPOINT ["/bin/sh", "/usr/local/bin/docker-entrypoint"]

FROM base AS fpm

CMD ["php-fpm"]

# ---------------------------------------------------------------------------
# All-in-one image for Railway (Nginx + PHP-FPM)
# ---------------------------------------------------------------------------
FROM base AS production

RUN apk add --no-cache nginx

COPY nginx-main.conf /etc/nginx/nginx.conf
COPY nginx-production.conf /etc/nginx/http.d/default.conf
COPY docker/start-production.sh /usr/local/bin/start-production.sh
RUN sed -i 's/\r$//' /usr/local/bin/start-production.sh \
    && chmod +x /usr/local/bin/start-production.sh

ENV APP_ENV=prod

RUN APP_ENV=prod APP_SECRET=build_secret \
    DATABASE_URL="sqlite:///%kernel.project_dir%/var/build.db" \
    php bin/console assets:install public --no-interaction \
    && php bin/console importmap:install --no-interaction \
    && php bin/console asset-map:compile --no-interaction \
    && php bin/console cache:warmup --no-interaction \
    && chown -R www-data:www-data var

# Railway sets PORT at runtime (often 8080); start-production.sh binds to $PORT
EXPOSE 8080

CMD ["/usr/local/bin/start-production.sh"]
