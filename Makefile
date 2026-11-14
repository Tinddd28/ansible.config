# сборка образов локально, перед запуском плейбуков
#   make caddy [CADDY_VERSION=2.11.9]
# версия должна совпадать с caddy_version в ansible (CADDY_VERSION из .env или дефолт роли)

CADDY_VERSION ?= 2.11.9
CADDY_IMAGE   := caddy-naive:$(CADDY_VERSION)
CADDY_CONTEXT := docker/caddy
# build-id: версия + хеш Dockerfile, ansible по нему проверяет актуальность образа
CADDY_BUILD_ID = $(CADDY_VERSION)-$(shell sha256sum $(CADDY_CONTEXT)/Dockerfile | cut -c1-12)

.PHONY: caddy
caddy:
	docker build \
		--build-arg CADDY_VERSION=$(CADDY_VERSION) \
		--label io.caddy-naive.build-id=$(CADDY_BUILD_ID) \
		-t $(CADDY_IMAGE) \
		$(CADDY_CONTEXT)
