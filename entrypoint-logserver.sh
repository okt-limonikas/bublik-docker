#!/bin/bash

setup_config_files() {
    echo "Updating configuration files with environment variables..."
    
    BUBLIK_FQDN=${BUBLIK_FQDN:-localhost}
    URL_PREFIX=${URL_PREFIX:-""}
    
    sed -i \
        -e "s,@@TE_INSTALL@@,/app/te/build/inst,g" \
        -e "s,/srv/logs,/home/te-logs/logs,g" \
        -e "s,root_dir=\"/srv/logs\",root_dir=\"/home/te-logs/logs\",g" \
        -e "s,@@BUBLIK_URL@@,${BUBLIK_FQDN}:${BUBLIK_DOCKER_PROXY_PORT}${URL_PREFIX},g" \
        -e "s,@@LOGS_URL@@,${BUBLIK_FQDN}:${BUBLIK_DOCKER_PROXY_PORT}${URL_PREFIX}/logs,g" \
        -e "s,@@LOGS_DIR@@,/home/te-logs/logs,g" \
        -e "s,@@LOGS_INCOMING@@,/home/te-logs/incoming,g" \
        -e "s,@@LOGS_BAD@@,/home/te-logs/bad,g" \
        /home/te-logs/cgi-bin/te-logs-index \
        /home/te-logs/cgi-bin/te-logs-error404 \
        /app/te/build/inst/default/bin/te-logs-error404.sh \
        /app/te/build/inst/default/bin/te-logs-index.sh \
        /home/te-logs/bin/publish-incoming-logs
    
    sed -i \
        -e "s,@@LOGS_CGI_BIN@@,/home/te-logs/cgi-bin,g" \
        -e "s,@@LOGS_DIR@@,/home/te-logs/logs,g" \
        -e "s,@@LOGS_URL_PATH@@,${URL_PREFIX}/logs,g" \
        /etc/apache2/conf-available/te-logs.conf
    
    echo "Configuration files updated successfully"
}

source /app/bublik/entrypoint-common.sh

setup_umask

echo "Setting up required directories..."
ensure_directory "/home/te-logs/logs"
ensure_directory "/home/te-logs/incoming"
ensure_directory "/home/te-logs/bad"
ensure_directory "/home/te-logs/cgi-bin"
ensure_directory "/home/te-logs/bin"

setup_permissions "/home/te-logs/logs" "/home/te-logs/incoming" "/home/te-logs/bad" "/home/te-logs/cgi-bin" "/home/te-logs/bin"


setup_config_files

setup_service_user "APACHE_RUN" "/etc/apache2/envvars"

echo "Starting Apache"
exec apache2ctl -D FOREGROUND