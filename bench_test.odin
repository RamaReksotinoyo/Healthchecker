package main

import "core:log"
import "core:mem"
import "core:testing"
import "core:time"

//"How many heap allocations does one /metrics render do?"
RUN_BENCH :: #config(BENCH, false)

@(test)
benchmark_metrics :: proc(t: ^testing.T) {
	if !RUN_BENCH {
		return // skipped unless built with -define:BENCH=true (see `make bench`)
	}

	targets := []Target {
		{name = "blog", url = "https://example.com"},
		{name = "grafana", url = "http://localhost:3000/api/health"},
		{name = "minio", url = "http://localhost:9000/minio/health/live"},
	}
	results := Results {
		ups         = []bool{true, false, false},
		latencies   = []f64{2.4, 0, 0},
		expiry_days = []i32{46, NO_EXPIRY, NO_EXPIRY},
	}

	// allocation count via the tracking allocator
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)

	old := context.allocator
	context.allocator = mem.tracking_allocator(&track)
	s := metrics_to_string(targets, results)
	delete(s)
	context.allocator = old // restore before measuring/cleanup

	log.infof(
		"one /metrics render: %d allocation(s), %d byte(s) total",
		track.total_allocation_count,
		track.total_memory_allocated,
	)
	mem.tracking_allocator_destroy(&track)

	// timing (ns/op)
	N :: 100_000
	start := time.tick_now()
	for _ in 0 ..< N {
		out := metrics_to_string(targets, results)
		delete(out)
	}
	ns := time.duration_nanoseconds(time.tick_since(start))
	log.infof("metrics_to_string: %d ns/op (avg over %d iters)", ns / N, N)
}
