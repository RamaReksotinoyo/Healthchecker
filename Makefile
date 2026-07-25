BINARY     := healthcheck
SRC        := .

VPS        ?= user@vps
REMOTE_DIR ?= /opt/healthcheck

.PHONY: help run build test clean build-linux deploy

help:
	@echo "Odin Healthcheck — make targets:"
	@echo "  make run          build & run locally (odin run .)"
	@echo "  make build        build a local binary -> ./$(BINARY)"
	@echo "  make test         run all @(test) procedures (odin test .)"
	@echo "  make build-linux  cross-compile optimized linux_amd64 binary"
	@echo "  make deploy       build-linux then scp to \$$VPS:\$$REMOTE_DIR"
	@echo "  make clean        remove built binary"

run:
	odin run $(SRC)

build:
	odin build $(SRC) -out:$(BINARY)

test:
	odin test $(SRC)

# Optimized build for the VPS (Linux x86-64).
build-linux:
	odin build $(SRC) -target:linux_amd64 -o:speed -out:$(BINARY)

# Requires SSH access to $(VPS). Copies the Linux binary to the remote dir.
deploy: build-linux
	scp $(BINARY) $(VPS):$(REMOTE_DIR)/

clean:
	rm -f $(BINARY)
