ORG     ?= $(shell basename $(realpath ..))
PKGS    := $(shell go list ./... | grep -v /vendor/)

build:
	go build -ldflags '-X github.com/roboll/helmfile/pkg/app/version.Version=${TAG}' ${TARGETS}
.PHONY: build

generate:
	go generate ${PKGS}
.PHONY: generate

fmt:
	go fmt ${PKGS}
.PHONY: fmt

check:
	go vet ${PKGS}
.PHONY: check

build-test-tools:
	go build test/diff-yamls/diff-yamls.go
	go build test/yamldiff/yamldiff.go
.PHONY: build-test-tools

test:
	go test -v ${PKGS} -cover -race -p=1
.PHONY: test

integration:
	bash test/integration/run.sh
.PHONY: integration

integration/vagrant:
	$(MAKE) build GOOS=linux GOARCH=amd64
	$(MAKE) build-test-tools GOOS=linux GOARCH=amd64
	vagrant up
	vagrant ssh -c 'HELMFILE_HELM3=1 make -C /vagrant integration'
.PHONY: integration/vagrant

cross:
	env CGO_ENABLED=0 gox -os 'windows darwin linux' -arch '386 amd64 arm64' -osarch '!darwin/386' -output "dist/{{.Dir}}_{{.OS}}_{{.Arch}}" -ldflags '-X github.com/roboll/helmfile/pkg/app/version.Version=${TAG}' ${TARGETS}
.PHONY: cross

static-linux:
	env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOFLAGS=-mod=readonly go build -o "dist/helmfile_linux_amd64" -ldflags '-X github.com/roboll/helmfile/pkg/app/version.Version=${TAG}' ${TARGETS}
.PHONY: static-linux

install:
	env CGO_ENABLED=0 go install -ldflags '-X github.com/roboll/helmfile/pkg/app/version.Version=${TAG}' ${TARGETS}
.PHONY: install

clean:
	rm dist/helmfile_*
.PHONY: clean

pristine: generate fmt
	git diff | cat
	git ls-files --exclude-standard --modified --deleted --others -x vendor  | grep -v '^go.' | diff /dev/null -
.PHONY: pristine

release: pristine cross
	@ghr -b ${BODY} -t ${GITHUB_TOKEN} -u ${ORG} ${TAG} dist
.PHONY: release

image:
	docker build -t quay.io/${ORG}/helmfile:${TAG} .

run: image
	docker run --rm -it -t quay.io/${ORG}/helmfile:${TAG} sh

push: image
	docker push quay.io/${ORG}/helmfile:${TAG}

image/debian:
	docker build -f Dockerfile.debian -t quay.io/${ORG}/helmfile:${TAG}-stable-slim .

push/debian: image/debian
	docker push quay.io/${ORG}/helmfile:${TAG}-stable-slim

tools:
	go get -u github.com/tcnksm/ghr github.com/mitchellh/gox
.PHONY: tools

TAG  = $(shell git describe --tags --abbrev=0 HEAD)
LAST = $(shell git describe --tags --abbrev=0 HEAD^)
BODY = "`git log ${LAST}..HEAD --oneline --decorate` `printf '\n\#\#\# [Build Info](${BUILD_URL})'`"

release/minor:
	git checkout master
	git pull --rebase origin master
	bash -c 'if git branch | grep autorelease; then git branch -D autorelease; else echo no branch to be cleaned; fi'
	git checkout -b autorelease origin/master
	bash -c 'SEMTAG_REMOTE=origin hack/semtag final -s minor'
	git checkout master

release/patch:
	git checkout master
	git pull --rebase origin master
	bash -c 'if git branch | grep autorelease; then git branch -D autorelease; else echo no branch to be cleaned; fi'
	git checkout -b autorelease origin/master
	bash -c 'SEMTAG_REMOTE=origin hack/semtag final -s patch'
	git checkout master
