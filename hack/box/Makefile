.PHONY: *

IMAGE ?= artefactual/ambox
TAG ?= test
SEED_CACHE_IMAGE ?= ghcr.io/sevein/ambox-build-cache
AM_SEED_KEY ?= $(shell ./scripts/seed/key.sh)
AM_SEED_CACHE_IMAGE ?= $(SEED_CACHE_IMAGE):seed-$(AM_SEED_KEY)

build:
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
