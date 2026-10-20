# Image implementation of template-base's release contract (docs/TEMPLATE.md,
# "Release: a Makefile contract"). release.yml sets RELEASE_VERSION /
# RELEASE_TAG / RELEASE_ARCH / OCI_* -- see there. Per-instance values go in
# the optional image.mk (every variable below is `?=`); steps beyond the
# generic ones are extra prerequisites of release-check, set there too.
# Template-owned: a sync overwrites this file.

-include image.mk

.PHONY: release-arches build sbom release-assets publish release-check finalize image-smoke check-arch
.DEFAULT_GOAL := release-arches

DOCKERFILE ?= Dockerfile
TARGET ?= runner
ARCHES ?= amd64 arm64
BUILD_ARGS ?=
EXTRA_LABELS ?=
OCI_DESCRIPTION ?=
OCI_LICENSE ?= GPL-3.0-or-later
COVERAGE_REPORT ?=
IMAGE_SMOKE_PORT ?= 8000
IMAGE_SMOKE_PATH ?= /health/live
IMAGE_SMOKE_RUN_ARGS ?=
IMAGE_SMOKE_TIMEOUT ?= 60

# renovate: datasource=docker depName=anchore/syft
SYFT_VERSION := v1.52.0

REPO := $(or $(GITHUB_REPOSITORY),$(notdir $(CURDIR)))
OWNER := $(firstword $(subst /, ,$(REPO)))
IMAGE := $(notdir $(REPO))
ASSET_PREFIX := dist/$(IMAGE)-$(RELEASE_VERSION)
ASSET := $(ASSET_PREFIX)-$(RELEASE_ARCH)
RELEASE_URL := https://github.com/$(REPO)/releases/download/$(RELEASE_TAG)
OCI_NAME := $(shell printf '%s' '$(or $(OCI_IMAGE_NAME),$(REPO))' | tr '[:upper:]' '[:lower:]')

# Only set in CI, by crazy-max/ghaction-github-runtime in release.yml.
ifdef ACTIONS_RUNTIME_TOKEN
CACHE := --cache-from type=gha,scope=$(RELEASE_ARCH) --cache-to type=gha,mode=max,scope=$(RELEASE_ARCH)
endif

# `created` is the commit time so build and publish produce identical labels
# (and therefore the same image) in separate make invocations. Description
# and coverage-report are emitted only when set.
LABELS := \
	--label org.opencontainers.image.title=$(IMAGE) \
	--label org.opencontainers.image.source=https://github.com/$(REPO) \
	--label org.opencontainers.image.url=https://github.com/$(REPO) \
	--label org.opencontainers.image.version=$(RELEASE_VERSION) \
	--label org.opencontainers.image.revision=$(shell git rev-parse HEAD) \
	--label org.opencontainers.image.created=$(shell git log -1 --format=%cI) \
	--label org.opencontainers.image.licenses=$(OCI_LICENSE) \
	--label io.github.$(OWNER).sbom=$(RELEASE_URL)/$(IMAGE)-$(RELEASE_VERSION)-$(RELEASE_ARCH).spdx.json
ifneq ($(OCI_DESCRIPTION),)
LABELS += --label "org.opencontainers.image.description=$(OCI_DESCRIPTION)"
endif
ifneq ($(COVERAGE_REPORT),)
LABELS += --label io.github.$(OWNER).coverage-report=$(RELEASE_URL)/$(COVERAGE_REPORT)
endif
LABELS += $(EXTRA_LABELS)

BUILD = docker buildx build -f $(DOCKERFILE) --target $(TARGET) \
	--platform linux/$(RELEASE_ARCH) $(BUILD_ARGS) $(LABELS) $(CACHE)

check-arch:
	@test -n "$(RELEASE_ARCH)" || { echo "RELEASE_ARCH is not set." >&2; exit 1; }

release-arches:
	@printf '[%s]\n' "$$(printf '"%s",' $(ARCHES) | sed 's/,$$//')"

build: check-arch
	mkdir -p dist
	$(BUILD) --output type=oci,dest=$(ASSET).tar .

sbom: check-arch
	docker run --rm -v "$(CURDIR)/dist:/dist" anchore/syft:$(SYFT_VERSION) \
		oci-archive:/$(ASSET).tar -o spdx-json=/$(ASSET).spdx.json

release-assets: check-arch
	test -f $(ASSET).tar && test -f $(ASSET).spdx.json

publish: check-arch
ifeq ($(OCI_REGISTRY),)
	@echo "OCI_REGISTRY not set -- skipping publish."
else
	@printf '%s' "$$OCI_REGISTRY_PASSWORD" | docker login "$(OCI_REGISTRY)" -u "$$OCI_REGISTRY_USERNAME" --password-stdin
	$(BUILD) --push -t $(OCI_REGISTRY)/$(OCI_NAME):$(RELEASE_VERSION)-$(RELEASE_ARCH) .
endif

image-smoke:
	IMAGE_TAR_PREFIX=$(ASSET_PREFIX) \
	IMAGE_SMOKE_PORT=$(IMAGE_SMOKE_PORT) IMAGE_SMOKE_PATH=$(IMAGE_SMOKE_PATH) \
	IMAGE_SMOKE_RUN_ARGS='$(IMAGE_SMOKE_RUN_ARGS)' IMAGE_SMOKE_TIMEOUT=$(IMAGE_SMOKE_TIMEOUT) \
	bash scripts/image-smoke.sh

# No recipe by design: image.mk adds steps as prerequisites, so Make never
# sees two recipes for one target.
release-check: image-smoke

finalize:
ifeq ($(OCI_REGISTRY),)
	@echo "OCI_REGISTRY not set -- no manifest list to create."
else
	@printf '%s' "$$OCI_REGISTRY_PASSWORD" | docker login "$(OCI_REGISTRY)" -u "$$OCI_REGISTRY_USERNAME" --password-stdin
	docker buildx imagetools create --tag $(OCI_REGISTRY)/$(OCI_NAME):$(RELEASE_VERSION) \
		$(foreach a,$(ARCHES),$(OCI_REGISTRY)/$(OCI_NAME):$(RELEASE_VERSION)-$(a))
endif
