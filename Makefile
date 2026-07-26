BINARY     := healthcheck
SRC        := .

VPS        ?= user@vps
REMOTE_DIR ?= /opt/healthcheck

# Benchmark test to run via `make bench`.
BENCH      := main.benchmark_metrics

.PHONY: help run build test bench clean build-linux deploy

help:
	@echo "Odin Healthcheck — make targets:"
	@echo "  make run          build & run locally (odin run .)"
	@echo "  make build        build a local binary -> ./$(BINARY)"
	@echo "  make test         run all @(test) procedures (odin test .)"
	@echo "  make bench        run only the benchmark, optimized (-o:speed)"
	@echo "  make build-linux  cross-compile optimized linux_amd64 binary"
	@echo "  make deploy       build-linux then scp to \$$VPS:\$$REMOTE_DIR"
	@echo "  make clean        remove built binary"

run:
	odin run $(SRC)

build:
	odin build $(SRC) -out:$(BINARY)

test:
	odin test $(SRC)

# Run only the benchmark, built optimized so timings reflect release code.
# -define:BENCH=true unlocks the gated benchmark body; `make test` leaves it off.
bench:
	odin test $(SRC) -o:speed -define:BENCH=true -define:ODIN_TEST_NAMES=$(BENCH)

# Optimized build for the VPS (Linux x86-64).
build-linux:
	odin build $(SRC) -target:linux_amd64 -o:speed -out:$(BINARY)

# Requires SSH access to $(VPS). Copies the Linux binary to the remote dir.
deploy: build-linux
	scp $(BINARY) $(VPS):$(REMOTE_DIR)/

clean:
	rm -f $(BINARY)
