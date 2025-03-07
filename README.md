<!--toc:start-->

- [📋 Prerequisites](#📋-prerequisites)
- [🚀 Getting Started](#🚀-getting-started)
- [📝 Common Tasks](#📝-common-tasks)
  - [Starting and Stopping the Application](#starting-and-stopping-the-application)
  - [Importing Logs](#importing-logs)
  - [Clean Environment](#clean-environment)
- [🔑 Default Credentials](#🔑-default-credentials)
- [📚 Environment Variables](#📚-environment-variables)
- [🐳 Docker Compose Files](#🐳-docker-compose-files)
- [🔍 Additional Notes](#🔍-additional-notes)
- [🛠️ Environment Configuration](#🛠️-environment-configuration)
  - [1. Initialise Project](#1-initialise-project)
  - [2. Configure Environment](#2-configure-environment)
  - [3. Start the Application](#3-start-the-application)
  <!--toc:end-->

## 📋 Prerequisites

Before getting started, ensure you have the following dependencies installed:

- Docker and Docker Compose
- jq (JSON processor)
- curl
- Taskfile

On Ubuntu/Debian systems, you can install the required dependencies with:

```bash
# Install Docker using convenience script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install jq and curl
sudo apt-get install jq curl
```

To install Taskfile refer to
<https://taskfile.dev/installation/>

## 🚀 Getting Started

💡 **Tip**: You can view available commands by running `task`

1. Initialise the environment:

```bash
task init     # Initialise Git submodules
task setup    # Set up Docker environment
```

If you don't want to customise anything and just start you can run.
These commands will ask if you want to create configs and import some sessions for start

2. Bootstrap the application:

```bash
# For development environment
task bootstrap-dev

# For production environment
task bootstrap
```

## 📝 Common Tasks

### Starting and Stopping the Application

```bash
# Start development environment
task dev:up

# Start development environment with watch mode
task dev:watch

# Stop development environment
task dev:down

# Start production environment
task up

# Stop production environment
task down
```

### Importing Logs

To import logs from a tar file:

```bash
task import-logs -- ./path/to/file.tar
```

### Clean Environment

To remove all containers, volumes, and unused images:

```bash
task nuke
```

⚠️ Warning: This will remove all data!

## 🔑 Default Credentials

After bootstrap, you can access the application with these default credentials:

- Email: <admin@bublik.com>
- Password: admin

## 📚 Environment Variables

The `.env.local` file contains default configuration values. After initial setup, you can modify the `.env` file to customize your environment.

## 🐳 Docker Compose Files

- `docker-compose.yml` - Production configuration
- `docker-compose.dev.yml` - Development configuration with hot-reload

## 🔍 Additional Notes

- Development environment includes hot-reload functionality
- All tasks can be listed using `task --list`

## 🛠️ Environment Configuration

Before starting the application, you can customise various settings like `URL_PREFIX`, admin credentials, and more:

### 1. Initialise Project

```bash
task init        # Initialise Git submodules
task setup      # Set up Docker environment
```

### 2. Configure Environment

Edit the `.env` file to customise your settings:

```env
# Admin credentials
DJANGO_SUPERUSER_EMAIL=your.email@example.com
DJANGO_SUPERUSER_PASSWORD=your-secure-password

# Application URL prefix (e.g., "/bublik" for http://localhost/bublik/)
URL_PREFIX=/your-prefix

# Other settings...
BUBLIK_WEB_NAME=Your Site Name
DOCS_URL=http://your-docs-url
```

### 3. Start the Application

```bash
# For production
task up

# For development (includes hot-reload)
task dev:up
```

💡 **Tip**: After changing environment variables, you'll need to restart the application for the changes to take effect.
