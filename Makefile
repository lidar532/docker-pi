# Generic pi-in-docker image builder and exporter.
#
# Defaults:
#   IMAGE    = docker.io/lidar532/pi-in-docker
#   VERSION  = latest
#
# Examples:
#   make build                 # build for current host architecture
#   make build-amd64           # build linux/amd64 image
#   make build-arm64           # build linux/arm64/v8 image (Pi 4/5, Pi 3B 64-bit, ARM servers)
#   make export-all            # build and save both architectures as tarballs
#   make push-amd64            # push amd64 image to Docker Hub

IMAGE   ?= docker.io/lidar532/pi-in-docker
VERSION ?= latest

UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
  HOST_ARCH := amd64
endif
ifeq ($(UNAME_M),aarch64)
  HOST_ARCH := arm64
endif
ifeq ($(UNAME_M),arm64)
  HOST_ARCH := arm64
endif

.PHONY: help build build-amd64 build-arm64 build-all export export-amd64 export-arm64 export-all clean push push-amd64 push-arm64

help:
	@echo "Targets:"
	@echo "  build          Build for the current host architecture ($(HOST_ARCH))"
	@echo "  build-amd64    Build linux/amd64 image"
	@echo "  build-arm64    Build linux/arm64/v8 image"
	@echo "  build-all      Build both amd64 and arm64 images"
	@echo "  export         Build and save current-arch tarball to dist/"
	@echo "  export-amd64   Build and save amd64 tarball to dist/"
	@echo "  export-arm64   Build and save arm64 tarball to dist/"
	@echo "  export-all     Build and save both tarballs to dist/"
	@echo "  push-amd64     Push amd64 image to Docker Hub"
	@echo "  push-arm64     Push arm64 image to Docker Hub"
	@echo "  clean          Remove dist/ directory"

build-amd64:
	docker buildx build --platform linux/amd64 -t $(IMAGE):$(VERSION)-amd64 .

build-arm64:
	docker buildx build --platform linux/arm64/v8 -t $(IMAGE):$(VERSION)-arm64 .

build-all: build-amd64 build-arm64

build: build-$(HOST_ARCH)

export-amd64: build-amd64
	mkdir -p dist
	docker save $(IMAGE):$(VERSION)-amd64 | gzip > dist/pi-in-docker-$(VERSION)-amd64.tar.gz

export-arm64: build-arm64
	mkdir -p dist
	docker save $(IMAGE):$(VERSION)-arm64 | gzip > dist/pi-in-docker-$(VERSION)-arm64.tar.gz

export: export-$(HOST_ARCH)

export-all: export-amd64 export-arm64

push-amd64: build-amd64
	docker push $(IMAGE):$(VERSION)-amd64

push-arm64: build-arm64
	docker push $(IMAGE):$(VERSION)-arm64

push: push-amd64 push-arm64

clean:
	rm -rf dist
