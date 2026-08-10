.PHONY: *

IMAGE ?= artefactual/ambox
TAG ?= test
AMBOX_RUN_ARGS ?=
AMBOX_DASHBOARD_PORT ?= 64080
AMBOX_STORAGE_PORT ?= 64081
AMBOX_SFTP_PORT ?= 64022
AMBOX_DASHBOARD_URL ?= http://127.0.0.1:$(AMBOX_DASHBOARD_PORT)
AMBOX_STORAGE_URL ?= http://127.0.0.1:$(AMBOX_STORAGE_PORT)

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

sampledata-image:
	./scripts/provision-sampledata.sh image

sampledata-e2e:
	./scripts/provision-sampledata.sh e2e

build: sampledata-image
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
	$(MAKE) run-image

run-image:
	docker run --name=ambox-test --rm \
		-p$(AMBOX_DASHBOARD_PORT):64080 \
		-p$(AMBOX_STORAGE_PORT):64081 \
		-p$(AMBOX_SFTP_PORT):64022 \
		-v $(CURDIR)/test/ambox.yaml:/etc/ambox/config.yaml:ro \
		-v $(CURDIR)/test/ssh_host_ed25519_key:/etc/ambox/sftpgo_host_key:ro \
		$(AMBOX_RUN_ARGS) $(IMAGE):$(TAG)

verify: sampledata-e2e
	uv run --project $(CURDIR)/e2e --locked \
		playwright install chromium
	AMBOX_DASHBOARD_URL="$(AMBOX_DASHBOARD_URL)" \
	AMBOX_STORAGE_URL="$(AMBOX_STORAGE_URL)" \
	AMBOX_SFTP_PORT="$(AMBOX_SFTP_PORT)" \
		uv run --project $(CURDIR)/e2e --locked \
		pytest -c $(CURDIR)/e2e/pyproject.toml \
		--output=$(CURDIR)/e2e/output/playwright \
		$(CURDIR)/e2e

sftp-publickey:
	sftp \
		-P $(AMBOX_SFTP_PORT) \
		-o StrictHostKeyChecking=yes \
		-o UserKnownHostsFile=$(CURDIR)/test/known_hosts \
		-i $(CURDIR)/test/ssh_user_ed25519_key \
		archivematica@localhost

sftp-password:
	sftp \
		-P $(AMBOX_SFTP_PORT) \
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
