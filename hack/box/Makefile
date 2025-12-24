.PHONY: *

IMAGE ?= artefactual/ambox
TAG ?= test

build:
	docker build --progress=plain -t $(IMAGE):$(TAG) -f Dockerfile $(CURDIR)/../../

buildx-publish:
	docker buildx build \
		--progress=plain \
		--platform linux/amd64,linux/arm64 \
		--push \
		-t ghcr.io/sevein/ambox:$(TAG) \
		-t artefactual/ambox:$(TAG) \
		-f Dockerfile \
		$(CURDIR)/../../

run: build
	docker run --rm -p64080:64080 -p64081:64081 -p64022:64022 $(IMAGE):$(TAG)

shell: build
	docker run --rm -it --entrypoint=bash $(IMAGE):$(TAG)
