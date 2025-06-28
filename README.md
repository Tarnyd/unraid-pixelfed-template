# Pixelfed Docker Template for Unraid

This repository contains all the necessary files to build a robust, production-ready Docker image for Pixelfed, tailored for use with Unraid.

This project was created to provide a reliable and up-to-date container, including all necessary dependencies for full functionality (image processing, video support, background jobs, etc.).

## Features

-   **Multi-Stage Dockerfile:** Creates a lean final image by separating the build environment from the production environment.
-   **Supervisor-managed:** Uses Supervisor to reliably manage Nginx, PHP-FPM, Horizon (for queues), and the Task Scheduler.
-   **Automated Setup:** Includes an `entrypoint.sh` script that handles first-time setup automatically, including database migrations and key generation.
-   **All Dependencies Included:** Comes with `ffmpeg`, `ImageMagick`, `jpegoptim`, and all required PHP extensions for a fully-featured Pixelfed instance.

## Prerequisites

Before you begin, you will need:
-   An Unraid server with Docker installed.
-   A separate, running **MariaDB/MySQL** database.
-   A separate, running **Redis** instance.
-   A Docker Hub account to push your built image to.

## How to Use

### 1. Build and Push the Docker Image

1.  **Clone this repository** to your local machine.
2.  Navigate into the project directory in your terminal.
3.  **Build the Docker image.** Replace `yourdockerhubusername` with your actual Docker Hub username.
    ```sh
    docker build -t yourdockerhubusername/pixelfed:latest .
    ```
4.  **Log in to Docker Hub:**
    ```sh
    docker login
    ```
5.  **Push the image** to Docker Hub:
    ```sh
    docker push yourdockerhubusername/pixelfed:latest
    ```

### 2. Add the Template to Unraid

1.  **Access your Unraid flash drive** via a network share (e.g., `\\UNRAID-IP\flash`).
2.  Navigate to the folder: `config/plugins/dockerMan/templates-user/`. If `templates-user` does not exist, create it.
3.  Copy the `pixelfed-unraid-template.xml` file from this repository into that folder.
4.  In the Unraid Web UI, go to the **Docker** tab and click **Add Container**.
5.  Select your new "Pixelfed-Tarnyd" template from the **Template** dropdown menu.

### 3. Configure and Run

1.  Fill in all the required variables in the Unraid template, especially:
    -   `App URL` and `App Domain`
    -   Database and Redis connection details
    -   SMTP settings for email
2.  Click **Apply** to start the container. The `entrypoint.sh` script will automatically run the initial setup (migrations, key generation, etc.).

### 4. Final Manual Step: Grant Admin Privileges

After the container is running and you have created your user account through the web interface:

1.  Open the Unraid console for the Pixelfed container.
2.  Run the following command, replacing `<your-username>` with the username you just created:
    ```sh
    php artisan user:admin <your-username>
    ```
3.  Restart the container from the Unraid UI for all changes to take full effect.

You are now ready to go!

## Project Files

-   `Dockerfile`: The main file for building the multi-stage Docker image.
-   `entrypoint.sh`: A helper script that runs on container start to prepare the environment and run the initial setup.
-   `nginx.conf`: The Nginx site configuration file.
-   `pixelfed.conf`: The Supervisor configuration file, managing all necessary processes.
-   `uploads.ini`: Custom PHP settings for file uploads.
-   `pixelfed-unraid-template.xml`: The Unraid template file for easy deployment.
-   `pixelfed-icon.png`: The icon used in the Unraid template.

## License

This project is open-source and available under the [MIT License](LICENSE).