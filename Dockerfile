# Use the base image of your choice
FROM ubuntu:latest

# Install required packages and add the Nginx repository
RUN apt-get update && apt-get install -y vim net-tools iputils-ping plocate apt-utils autoconf automake build-essential git libcurl4-openssl-dev libgeoip-dev liblmdb-dev libpcre++-dev libtool libxml2-dev libyajl-dev wget zlib1g-dev software-properties-common  gcc make build-essential autoconf automake libtool libcurl4-openssl-dev liblua5.3-dev libfuzzy-dev ssdeep gettext libpcre3 libpcre3-dev libxml2 libxml2-dev libcurl4 libgeoip-dev libyajl-dev doxygen git dpkg-dev curl gnupg2 ca-certificates lsb-release ubuntu-keyring software-properties-common git sudo && \
    curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null && \
    gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list && \
    apt-get update && \
    add-apt-repository ppa:ondrej/nginx-mainline -y && \
    apt-get install -y nginx-full && \
    apt-get clean -y && apt-get purge -y && apt-get autoremove -y

# Create a directory for ModSecurity and build it
RUN mkdir -p /usr/local/src/nginx/ && \
    cd /usr/local/src/nginx/ && \
    git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity && \
    cd ModSecurity && \
    git submodule init && \
    git submodule update && \
    ./build.sh && \
    ./configure && \
    make && \
    make install

# Create a directory for the ModSecurity NGINX connector and clone the repository
RUN mkdir -p /usr/local/modsecurity/ && \
    cd /usr/local/modsecurity/ && \
    git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git

# Check the current version of Nginx installed and download its tar file
RUN nginx -v && \
    NGINX_VERSION=$(nginx -v 2>&1 | grep -oE 'nginx/([0-9]+\.[0-9]+\.[0-9]+)' | cut -d'/' -f2) && \
    curl -O http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar zxvf nginx-${NGINX_VERSION}.tar.gz && \
    cd nginx-${NGINX_VERSION} && \
    ./configure --with-compat --add-dynamic-module=/usr/local/modsecurity/ModSecurity-nginx && \
    make modules && \
    cp objs/ngx_http_modsecurity_module.so /usr/share/nginx/modules/ && \
    cd .. && \
    rm -rf nginx-${NGINX_VERSION}*

# Add the line at the top of /etc/nginx/nginx.conf
RUN echo "## Nginx ModSecurity Connector\nload_module modules/ngx_http_modsecurity_module.so;" | cat - /etc/nginx/nginx.conf > temp && mv temp /etc/nginx/nginx.conf

# Create ModSecurity configuration directory and download the recommended configuration
RUN mkdir -p /etc/nginx/modsec && \
    cd /etc/nginx/modsec && \
    wget https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended && \
    mv modsecurity.conf-recommended modsecurity.conf

# Copy unicode.mapping file
RUN cp /usr/local/src/nginx/ModSecurity/unicode.mapping /etc/nginx/modsec/

# Replace "SecRuleEngine DetectionOnly" with "SecRuleEngine On"
RUN sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/nginx/modsec/modsecurity.conf && \
    sed -i 's/SecAuditLogParts ABIJDEFHZ/SecAuditLogParts ABCEFHJKZ/' /etc/nginx/modsec/modsecurity.conf && \
    sed -i 's/SecResponseBodyAccess On/SecResponseBodyAccess Off/' /etc/nginx/modsec/modsecurity.conf 


# Add the lines to the "http" section of nginx.conf
RUN sed -i '/http {/a \## Enabling modsecurity module configuration\n        modsecurity on;\n        modsecurity_rules_file /etc/nginx/modsec/main.conf;' /etc/nginx/nginx.conf

# Create the ModSecurity and Core Rule Set directories
RUN mkdir -p /etc/nginx/modsec && \
    cd /etc/nginx/modsec && \
    git clone https://github.com/coreruleset/coreruleset.git && \
    cd /etc/nginx/modsec/coreruleset && \
    cp crs-setup.conf.example crs-setup.conf && \
    echo "        # Include the recommended configuration" >> /etc/nginx/modsec/main.conf && \
    echo "        Include /etc/nginx/modsec/modsecurity.conf" >> /etc/nginx/modsec/main.conf && \
    echo "        # Other ModSecurity Rules" >> /etc/nginx/modsec/main.conf && \
    echo "        Include /etc/nginx/modsec/coreruleset/crs-setup.conf" >> /etc/nginx/modsec/main.conf && \
    echo "        Include /etc/nginx/modsec/coreruleset/rules/*.conf" >> /etc/nginx/modsec/main.conf

# Perform Nginx configuration test
RUN service nginx configtest

# Start the Nginx service
ENTRYPOINT ["nginx", "-g", "daemon off;"]

# Other Dockerfile instructions as needed
