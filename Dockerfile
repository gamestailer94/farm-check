FROM alpine:latest

# Install build dependencies
RUN apk add --no-cache \
    subversion \
    automake \
    autoconf \
    build-base \
    libtool \
    linux-headers \
    pciutils-dev \
    libcap-ng-dev \
    bash

# Get the source
RUN svn co https://svn.code.sf.net/p/smartmontools/code/trunk/smartmontools /opt/smartmontools

# Run autogen.sh
RUN cd /opt/smartmontools && \
    ./autogen.sh && \
    ./configure && \
    make -j$(nproc) && \
    make install

# Add the 'check.sh' script
COPY check.sh /entrypoint.sh

# Make sure it's executable
RUN chmod +x /entrypoint.sh

# Run it
ENTRYPOINT ["/entrypoint.sh"]
