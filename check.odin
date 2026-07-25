package main

import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:time"

// is_up reports whether an HTTP status code counts as "up" (any 2xx)
is_up :: proc(status_code: int) -> bool {
	return status_code >= 200 && status_code < 300
}

// Extracts the numeric code from an HTTP status line such as
// "HTTP/1.1 200 OK". Returns ok=false if the line is malformed
parse_status_code :: proc(status_line: string) -> (code: int, ok: bool) {
	fields := strings.fields(status_line)
	defer delete(fields)
	if len(fields) < 2 || !strings.has_prefix(fields[0], "HTTP/") {
		return 0, false
	}
	return strconv.parse_int(fields[1], 10)
}

// check_http performs one plain-HTTP request over a raw TCP socket and reports
// up/down plus latency in seconds. A dial, send, or receive failure 
// (timeout, connection refused, 5xx) all yield up=false.
check_http :: proc(target: Target) -> (up: bool, latency_seconds: f64) {
	// split_url allocates the queries map; free it. scheme/fragment are unused.
	_, host, path, queries, _ := net.split_url(target.url)
	defer delete(queries)

	// Ensure a host:port string for dialing; default HTTP port is 80.
	host_port := host
	if strings.index_byte(host, ':') < 0 {
		host_port = strings.concatenate({host, ":80"})
	}
	defer if host_port != host {
		delete(host_port)
	}

	req_path := path if path != "" else "/"

	start := time.tick_now()

	socket, dial_err := net.dial_tcp_from_hostname_and_port_string(host_port)
	if dial_err != nil {
		return false, 0
	}
	defer net.close(socket)

	req := fmt.tprintf(
		"GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\nUser-Agent: odin-healthcheck\r\n\r\n",
		req_path,
		host,
	)
	if _, send_err := net.send_tcp(socket, transmute([]byte)req); send_err != nil {
		return false, 0
	}

	// The status line is in the first packet; a small buffer is enough.
	buf: [1024]byte
	n, recv_err := net.recv_tcp(socket, buf[:])
	if recv_err != nil || n == 0 {
		return false, 0
	}

	latency_seconds = time.duration_seconds(time.tick_since(start))

	response := string(buf[:n])
	status_line := response
	if line_end := strings.index(response, "\r\n"); line_end >= 0 {
		status_line = response[:line_end]
	}

	code, ok := parse_status_code(status_line)
	if !ok {
		return false, latency_seconds
	}
	return is_up(code), latency_seconds
}

// One full check cycle, filling results in place (indexed in parallel with targets). 
// The tagged enum + switch lets the compiler inline each
// branch instead of dispatching through an interface. 
// HTTPS is stubbed until the TLS path (step 3b) lands.
run_checks :: proc(targets: []Target, results: Results) {
	for target, i in targets {
		switch check_kind_for(target.url) {
		case .HTTP:
			up, latency := check_http(target)
			results.ups[i] = up
			results.latencies[i] = latency
			results.expiry_days[i] = NO_EXPIRY
		case .HTTPS:
			// TODO(3b): TLS handshake for uptime + cert expiry.
			results.ups[i] = false
			results.latencies[i] = 0
			results.expiry_days[i] = NO_EXPIRY
		}
	}
}
