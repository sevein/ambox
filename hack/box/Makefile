.PHONY: *

IMAGE ?= artefactual/ambox
TAG ?= test

# Local seed-cache image repo used by `make build` / `make run` in development.
SEED_CACHE_IMAGE ?= ambox-build-cache-local

# Remote seed-cache image repo used by `make seed-cache` and local remote reuse.
SEED_CACHE_IMAGE_REMOTE ?= ghcr.io/sevein/ambox-build-cache

# Seed cache key derived from migration history + seed script changes.
AM_SEED_KEY ?= $(shell ./scripts/seed/key.sh)

# Fully qualified seed-cache image reference consumed by Dockerfile.
AM_SEED_CACHE_IMAGE ?= $(SEED_CACHE_IMAGE):seed-$(AM_SEED_KEY)

# Sentinel value that identifies the local-dev default repo for auto-seed setup.
SEED_CACHE_IMAGE_LOCAL_DEFAULT ?= ambox-build-cache-local

build:
	# In local dev, ensure the local seed-cache tag exists before `docker build`.
	# `seed-cache-local` reuses a matching remote seed when available and only
	# builds the seed locally if needed. Skip this when the caller explicitly
	# points `SEED_CACHE_IMAGE` at a remote repo.
	@if [ "$(SEED_CACHE_IMAGE)" = "$(SEED_CACHE_IMAGE_LOCAL_DEFAULT)" ]; then \
		$(MAKE) seed-cache-local; \
	fi
	docker build \
		--progress=plain \
		--build-arg AM_SEED_CACHE_IMAGE=$(AM_SEED_CACHE_IMAGE) \
		--build-arg AM_SEED_KEY=$(AM_SEED_KEY) \
		-t $(IMAGE):$(TAG) \
		-f Dockerfile \
		$(CURDIR)/../../

run: build
	docker run --name=ambox-test --rm \
		-p64080:64080 -p64081:64081 -p64022:64022 \
		-v $(CURDIR)/test/ambox.yaml:/etc/ambox/config.yaml:ro \
		-v $(CURDIR)/test/ssh_host_ed25519_key:/etc/ambox/sftpgo_host_key:ro \
		$(IMAGE):$(TAG)

sftp-publickey:
	sftp \
		-P 64022 \
		-o StrictHostKeyChecking=yes \
		-o UserKnownHostsFile=$(CURDIR)/test/known_hosts \
		-i $(CURDIR)/test/ssh_user_ed25519_key \
		archivematica@localhost

sftp-password:
	sftp \
		-P 64022 \
		-o StrictHostKeyChecking=yes \
		-o UserKnownHostsFile=$(CURDIR)/test/known_hosts \
		archivematica@localhost

shell: build
	docker run --name=ambox-test --rm -it --entrypoint=bash $(IMAGE):$(TAG)

seed-cache:
	SEED_CACHE_IMAGE_REPO=$(SEED_CACHE_IMAGE_REMOTE) ./scripts/seed/publish-cache.sh

seed-cache-local:
	SEED_CACHE_PUSH=0 \
	SEED_CACHE_IMAGE_REPO=$(SEED_CACHE_IMAGE) \
	SEED_CACHE_REMOTE_REPO=$(SEED_CACHE_IMAGE_REMOTE) \
	./scripts/seed/publish-cache.sh
