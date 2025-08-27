HOMEPAGE_CONTAINER ?= quay.io/validatedpatterns/homepage-container:main
UNAME=$(shell uname -s)

# Can't use host networks on MacOS as it's a VM anyway.
# Also because of the proxy 127.0.0.1 doesn't work as a bind address.
ifeq ($(UNAME), Darwin)
	PODMAN_OPTS ?= -it --security-opt label=disable --pull=newer -p 4000:4000
	HUGO_SERVER_OPTS = --bind 0.0.0.0 
else
	PODMAN_OPTS ?= -it --security-opt label=disable --pull=newer --net=host
endif
# Do not use selinux labeling when we are using nfs
FSTYPE=$(shell df -Th . | grep -v Type | awk '{ print $$2 }')

ifeq ($(FSTYPE), nfs)
	ATTRS = "rw"
else ifeq ($(FSTYPE), nfs4)
	ATTRS = "rw"
else ifeq ($(UNAME), Darwin)
	ATTRS = "rw"
else
	ATTRS = "rw,z"
endif

##@ Docs tasks

.PHONY: help
# No need to add a comment here as help is described in common/
help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^(\s|[a-zA-Z_0-9-])+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: test
test: htmltest ## Runs tests
	@echo "Ran all tests"

.PHONY: build
build: ## Build the website locally in the public/ folder
	podman run $(PODMAN_OPTS) -v $(PWD):/site:$(ATTRS) --entrypoint hugo $(HOMEPAGE_CONTAINER)

.PHONY: serve
serve: ## Build the website locally from a container and serve it
	@echo "Serving via container. Browse to http://localhost:4000"
	podman run $(PODMAN_OPTS) -v $(PWD):/site:$(ATTRS) --entrypoint hugo $(HOMEPAGE_CONTAINER) server -p 4000 $(HUGO_SERVER_OPTS)

.PHONY: htmltest
htmltest: build ## Runs htmltest against the site to find broken links
	@echo "Running html proof to check links"
	podman run $(PODMAN_OPTS) -v $(PWD):/site:$(ATTRS) --entrypoint htmltest $(HOMEPAGE_CONTAINER)

.PHONY: run
run: ## Runs the container interactively
	@echo "Running html proof to check links"
	podman run $(PODMAN_OPTS) -v $(PWD):/site:$(ATTRS) $(HOMEPAGE_CONTAINER)

.PHONY: update-container
update-container: ## Updates the container used for local testing
	podman pull $(HOMEPAGE_CONTAINER)

.PHONY: spellcheck
spellcheck: ## Runs a spellchecker on the content/ folder
	@echo "Running spellchecking on the tree"
	podman run $(PODMAN_OPTS) -v $(PWD):/tmp:$(ATTRS) docker.io/jonasbn/github-action-spellcheck:latest

.PHONY: lintwordlist
lintwordlist: ## Sorts and removes duplicates from spellcheck exception file .wordlist.txt
	@cp --preserve=all .wordlist.txt /tmp/.wordlist.txt
	@sort .wordlist.txt | tr '[:upper:]' '[:lower:]' | uniq > /tmp/.wordlist.txt
	@mv -v /tmp/.wordlist.txt .wordlist.txt

.PHONY: clean
clean: ## Removes any unneeded spurious files
	@rm -rvf ./.jekyll-cache ./_site ./tmp super-linter.log dictionary.dic public/*

.PHONY: super-linter
super-linter: ## Runs super linter locally
	rm -rf .mypy_cache
	podman run -e RUN_LOCAL=true -e USE_FIND_ALGORITHM=true	\
					-e VALIDATE_GITLEAKS=true \
					$(DISABLE_LINTERS) \
					-v $(PWD):/tmp/lint:rw,z \
					-w /tmp/lint \
					ghcr.io/super-linter/super-linter:slim-v7
