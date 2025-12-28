.PHONY: *

IMAGE ?= artefactual/ambox
TAG ?= test
SEED_CACHE_IMAGE ?= ghcr.io/sevein/ambox-build-cache
AM_SEED_KEY ?= $(shell ./scripts/seed/key.sh)
AM_SEED_CACHE_IMAGE ?= $(SEED_CACHE_IMAGE):seed-$(AM_SEED_KEY)

build:
	docker build --progress=plain \
		--build-arg AM_SEED_CACHE_IMAGE=$(AM_SEED_CACHE_IMAGE) \
		--build-arg AM_SEED_KEY=$(AM_SEED_KEY) \
		-t $(IMAGE):$(TAG) \
		-f Dockerfile \
		$(CURDIR)/../../

run: build
	docker run --rm -p64080:64080 -p64081:64081 -p64022:64022 $(IMAGE):$(TAG)

shell: build
	docker run --rm -it --entrypoint=bash $(IMAGE):$(TAG)
