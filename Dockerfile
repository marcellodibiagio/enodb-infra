FROM php:8.1-apache
RUN docker-php-ext-install mysqli 
RUN docker-php-ext-install pdo_mysql
RUN a2enmod rewrite
RUN a2enmod headers
RUN a2enmod ssl # [CLAUDE] abilita modulo SSL Apache
ADD /conf/custom.ini /usr/local/etc/php/conf.d/
# [CLAUDE] VirtualHost HTTPS
ADD /conf/enodb-ssl.conf /etc/apache2/sites-enabled/enodb-ssl.conf
RUN apt-get update -y --fix-missing
RUN apt-get install -y \
 unzip \
 libaio-dev \
 libmcrypt-dev git \
 && apt-get clean -y

# Oracle instantclient

# copy oracle files
ADD oracle/instantclient-basic-linux.x64-12.2.0.1.0.zip /tmp/
ADD oracle/instantclient-sdk-linux.x64-12.2.0.1.0.zip /tmp/
# unzip them
RUN unzip /tmp/instantclient-basic-linux.x64-12.2.0.1.0.zip -d /usr/local/ \
    && unzip /tmp/instantclient-sdk-linux.x64-12.2.0.1.0.zip -d /usr/local/

# install oci8
RUN ln -s /usr/local/instantclient_12_2 /usr/local/instantclient \
    && ln -s /usr/local/instantclient/libclntsh.so.12.1 /usr/local/instantclient/libclntsh.so \
    && ln -s /usr/local/instantclient/libocci.so.12.1 /usr/local/instantclient/libocci.so \
    && ln -s /usr/lib/x86_64-linux-gnu/libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1 # [CLAUDE] Bookworm: libaio rinominata

ENV LD_LIBRARY_PATH /usr/local/instantclient_12_2/

RUN docker-php-ext-configure pdo_oci --with-pdo-oci=instantclient,/usr/local/instantclient \
    && echo 'instantclient,/usr/local/instantclient' | pecl install oci8-3.2.1
RUN docker-php-ext-enable oci8 # [CLAUDE] abilita estensione OCI8 in PHP

# [CLAUDE] OpenSSL 3.x: abilita legacy TLS renegotiation per stampanti fiscali con TLS vecchio
RUN sed -i '/^\[openssl_init\]/a ssl_conf = ssl_sect' /usr/lib/ssl/openssl.cnf \
    && printf '\n[ssl_sect]\nsystem_default = system_default_sect\n\n[system_default_sect]\nOptions = UnsafeLegacyRenegotiation\n' >> /usr/lib/ssl/openssl.cnf