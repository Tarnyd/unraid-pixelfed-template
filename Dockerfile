# --- Stage 1: The Builder ---
# This stage installs all build tools and compiles the application and its assets.
FROM php:8.3-fpm AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Install all system dependencies, build tools, and media processors.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl unzip build-essential \
    libpng-dev libjpeg-dev libfreetype6-dev libzip-dev zlib1g-dev libicu-dev \
    libmagickwand-dev libwebp-dev libcurl4-openssl-dev libexif-dev libxml2-dev libssl-dev libonig-dev \
    ffmpeg jpegoptim optipng pngquant nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# Install the required PHP extensions.
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) \
        bcmath \
        pcntl \
        zip \
        gd \
        exif \
        intl \
        pdo_mysql

# Install PECL extensions.
RUN pecl install imagick redis \
    && docker-php-ext-enable imagick redis

# Install Composer.
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Set the working directory for the application build.
WORKDIR /app

# Clone the source and build the application.
RUN git clone -b dev https://github.com/pixelfed/pixelfed.git .
RUN sed -i "s/\$proxies = null;/\$proxies = '*';/" app/Http/Middleware/TrustProxies.php
RUN composer install --no-ansi --no-dev --no-interaction --optimize-autoloader
RUN npm install && npm run production


# --- Stage 2: The Final Production Image ---
# This stage is lean and only contains what's needed to run the application.
FROM php:8.3-fpm

ARG DEBIAN_FRONTEND=noninteractive

# Install only the required RUNTIME dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpng-dev libjpeg-dev libfreetype6-dev libzip-dev zlib1g-dev libicu-dev \
    libmagickwand-dev libwebp-dev libcurl4-openssl-dev libexif-dev libxml2-dev libssl-dev libonig-dev \
    ffmpeg jpegoptim optipng pngquant nginx supervisor \
    && rm -rf /var/lib/apt/lists/*

# Copy the pre-compiled PHP extensions from the builder stage.
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/

# Set the final working directory.
WORKDIR /var/www

# Copy the final application code and set permissions.
COPY --from=builder /app .
RUN chown -R www-data:www-data /var/www

# Copy all configuration files.
COPY uploads.ini /usr/local/etc/php/conf.d/uploads.ini
COPY nginx.conf /etc/nginx/sites-available/default
COPY pixelfed.conf /etc/supervisor/conf.d/pixelfed.conf
RUN ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Copy and set the entrypoint script.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

EXPOSE 80

# The main command to run the application via Supervisor.
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/pixelfed.conf"]