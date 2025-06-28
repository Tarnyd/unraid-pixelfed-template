#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# FIX: Ensure a .env file exists so Artisan commands can run.
# Laravel will load this file, and then overwrite the values with Docker's environment variables.
if [ ! -f /var/www/.env ]; then
    echo "Creating .env file from example..."
    cp /var/www/.env.example /var/www/.env
fi

# Create all necessary directories on every start to handle empty volumes.
# This solves the Supervisor startup error.
mkdir -p /var/www/storage/framework/cache/data
mkdir -p /var/www/storage/framework/sessions
mkdir -p /var/www/storage/framework/views
mkdir -p /var/www/storage/logs
mkdir -p /var/www/bootstrap/cache

# Set the correct permissions on every start.
chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache

# Run one-time setup if it hasn't been done before.
# Checks if the database has been migrated. If not, run the entire setup process.
if ! php /var/www/artisan migrate:status --quiet; then
    echo "First run detected. Performing one-time setup..."

    # Generate APP_KEY if it's not set as an environment variable
    if [ -z "$APP_KEY" ]; then
        php /var/www/artisan key:generate --force
    fi

    # Run all necessary setup commands
    php /var/www/artisan migrate --force
    php /var/www/artisan passport:keys --force
    php /var/www/artisan storage:link --force

    # Clear and re-cache everything
    php /var/www/artisan config:cache
    php /var/www/artisan route:cache
    php /var/www/artisan view:cache

    echo "One-time setup complete!"
fi

# Execute the command passed to this script.
# This will be 'supervisord ...' from the Dockerfile's CMD.
exec "$@"