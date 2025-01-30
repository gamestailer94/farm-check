FROM alpine:latest
RUN apk add --no-cache smartmontools

COPY check.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]