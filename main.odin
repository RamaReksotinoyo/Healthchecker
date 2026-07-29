package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

CONFIG_PATH       :: "config.json"
INTERVAL_SECONDS  :: 30
FAILURE_THRESHOLD :: 3 // consecutive failures before a target is reported down (3 × 30s = up to 90s)
LISTEN_ADDR       :: "0.0.0.0" // bind address; use 127.0.0.1 to restrict to localhost
METRICS_PORT      :: 9101
METRICS_PATH      :: "/metrics"

// Cross-thread state: only `snapshot` is shared (guarded by `mu`); `results` is checker-only.
Shared :: struct {
	targets:  []Target,
	results:  Results, 
    mu:       sync.Mutex,
	snapshot: string,
}

main :: proc() {
	config, ok := load_config(CONFIG_PATH)
	if !ok {
		fmt.eprintfln("error: failed to load config from %q", CONFIG_PATH)
		os.exit(1)
	}
	defer delete_config(config)

	n := len(config.targets)
	results := Results {
		ups         = make([]bool, n),
		latencies   = make([]f64, n),
		expiry_days = make([]i32, n),
	}
	defer {
		delete(results.ups)
		delete(results.latencies)
		delete(results.expiry_days)
	}

	shared := Shared {
		targets = config.targets,
		results = results,
	}

	fmt.printfln("odin-healthcheck: %d target(s), interval %ds", n, INTERVAL_SECONDS)

	// The HTTP server runs on the main thread and blocks forever.
	_ = thread.create_and_start_with_poly_data(&shared, checker_loop)
	serve(&shared)
}

// checker_loop runs one check cycle per interval, forever
checker_loop :: proc(s: ^Shared) {
	// Per-target consecutive-failure counters (checker-thread-only, like prev_ups).
	fail_streak := make([]i32, len(s.targets))
	defer delete(fail_streak)
	// Track previous up/down per target so we log only when state changes.
	prev_ups := make([]bool, len(s.targets))
	defer delete(prev_ups)
	first_cycle := true

	for {
		run_checks(s.targets, s.results)

		for i in 0 ..< len(s.targets) {
			s.results.ups[i] = confirm_up(&fail_streak[i], s.results.ups[i], FAILURE_THRESHOLD)
		}

		// Log each target's initial state once, then only transitions afterwards.
		for target, i in s.targets {
			up := s.results.ups[i]
			switch {
			case first_cycle:
				fmt.printfln("target %q initial state: %s", target.name, up ? "UP" : "DOWN")
			case up != prev_ups[i]:
				fmt.printfln("target %q is now %s", target.name, up ? "UP" : "DOWN")
			}
			prev_ups[i] = up
		}
		first_cycle = false

		rendered := metrics_to_string(s.targets, s.results)

		sync.mutex_lock(&s.mu)
		old := s.snapshot
		s.snapshot = rendered
		sync.mutex_unlock(&s.mu)
		delete(old) // free the previous snapshot (nil on the first cycle — safe)

		free_all(context.temp_allocator) // check_http/check_https use tprintf
		time.sleep(INTERVAL_SECONDS * time.Second)
	}
}

serve :: proc(s: ^Shared) {
	endpoint_str := fmt.tprintf("%s:%d", LISTEN_ADDR, METRICS_PORT)
	ep, ok := net.parse_endpoint(endpoint_str)
	if !ok {
		fmt.eprintfln("error: bad listen endpoint %q", endpoint_str)
		os.exit(1)
	}

	listener, err := net.listen_tcp(ep)
	if err != nil {
		fmt.eprintfln("error: cannot listen on %s: %v", endpoint_str, err)
		os.exit(1)
	}
	fmt.printfln("serving metrics on http://%s%s", endpoint_str, METRICS_PATH)

	for {
		client, _, accept_err := net.accept_tcp(listener)
		if accept_err != nil {
			continue
		}
		handle_conn(s, client)
	}
}

// GET METRICS_PATH with the current snapshot; anything else gets a 404 
handle_conn :: proc(s: ^Shared, client: net.TCP_Socket) {
	defer net.close(client)

	buf: [2048]byte
	n, recv_err := net.recv_tcp(client, buf[:])
	if recv_err != nil || n == 0 {
		return
	}
	request := string(buf[:n])

	wanted := fmt.tprintf("GET %s ", METRICS_PATH)
	if !strings.has_prefix(request, wanted) {
		send_all(client, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
		return
	}

	sync.mutex_lock(&s.mu)
	body := strings.clone(s.snapshot)
	sync.mutex_unlock(&s.mu)
	defer delete(body)

	response := fmt.tprintf(
		"HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
		len(body),
		body,
	)
	send_all(client, response)
	free_all(context.temp_allocator)
}

// send_all writes the whole string to the socket, looping over partial sends.
send_all :: proc(client: net.TCP_Socket, data: string) {
	bytes := transmute([]byte)data
	for len(bytes) > 0 {
		sent, err := net.send_tcp(client, bytes)
		if err != nil || sent <= 0 {
			return
		}
		bytes = bytes[sent:]
	}
}
