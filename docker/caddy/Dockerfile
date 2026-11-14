# Caddy + forwardproxy (naive fork)
# собирается под архитектуру машины сборки, BuildKit/buildx не нужен: make caddy
ARG CADDY_VERSION=2.11.9

# версию xcaddy берёт из ENV CADDY_VERSION образа builder (она перекрывает ARG)
FROM caddy:${CADDY_VERSION}-builder AS builder
RUN xcaddy build \
      --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive \
      --output /usr/bin/caddy

FROM caddy:${CADDY_VERSION}
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
RUN ["/usr/bin/caddy", "list-modules", "--packages"]
