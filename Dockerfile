FROM alpine:latest
RUN apk add --no-cache smartmontools

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/check.sh"]