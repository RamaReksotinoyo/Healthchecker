package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

// is_up reports whether an HTTP status code counts as "up" (any 2xx)
is_up :: proc(status_code: int) -> bool {
	return status_code >= 200 && status_code < 300
}

// confirm_up debounces a raw result: down only after `threshold` failures in a row; any success clears the streak.
confirm_up :: proc(streak: ^i32, raw_up: bool, threshold: i32) -> bool {
	streak^ = 0 if raw_up else streak^ + 1
	return streak^ < threshold
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

// HTTPS / TLS via shell-out

// month_from_abbrev maps an English 3-letter month ("Sep") to 1..12. Pure/tested.
month_from_abbrev :: proc(mon: string) -> (int, bool) {
	switch mon {
	case "Jan": return 1, true
	case "Feb": return 2, true
	case "Mar": return 3, true
	case "Apr": return 4, true
	case "May": return 5, true
	case "Jun": return 6, true
	case "Jul": return 7, true
	case "Aug": return 8, true
	case "Sep": return 9, true
	case "Oct": return 10, true
	case "Nov": return 11, true
	case "Dec": return 12, true
	}
	return 0, false
}

// parse_openssl_enddate parses `openssl x509 -noout -enddate` output such as
// "notAfter=Sep  9 18:54:50 2026 GMT" into calendar fields
parse_openssl_enddate :: proc(s: string) -> (year, month, day: int, ok: bool) {
	after := strings.trim_space(s)
	if idx := strings.index(after, "="); idx >= 0 {
		after = after[idx + 1:]
	}
	// fields collapses the double space before a single-digit day.
	fields := strings.fields(after) // ["Sep","9","18:54:50","2026","GMT"]
	defer delete(fields)
	if len(fields) < 4 {
		return 0, 0, 0, false
	}
	mon, mon_ok := month_from_abbrev(fields[0])
	d, d_ok := strconv.parse_int(fields[1], 10)
	y, y_ok := strconv.parse_int(fields[3], 10)
	if !mon_ok || !d_ok || !y_ok {
		return 0, 0, 0, false
	}
	return y, mon, d, true
}

// days_from_civil returns the number of days since 1970-01-01 for a civil date
// (Howard Hinnant's algorithm)
days_from_civil :: proc(y, m, d: int) -> i64 {
	yy := i64(y)
	if m <= 2 {
		yy -= 1
	}
	era := (yy if yy >= 0 else yy - 399) / 400
	yoe := yy - era * 400
	mm := i64(m)
	doy := (153 * (mm + (-3 if m > 2 else 9)) + 2) / 5 + i64(d) - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468
}

// host_only extracts just the hostname (no scheme/port/path) from a URL.
host_only :: proc(url: string) -> string {
	_, host, _, queries, _ := net.split_url(url)
	delete(queries)
	if idx := strings.index_byte(host, ':'); idx >= 0 {
		return host[:idx]
	}
	return host
}

// cert_expiry_days shells out to openssl to read the peer certificate's notAfter
// date over a TLS handshake, then computes days until expiry (UTC). Impure.
cert_expiry_days :: proc(host: string) -> (days: i32, ok: bool) {
	cmd := fmt.tprintf(
		"echo | openssl s_client -connect %s:443 -servername %s 2>/dev/null | openssl x509 -noout -enddate",
		host,
		host,
	)
	_, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command = []string{"sh", "-c", cmd}},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	if err != nil {
		return 0, false
	}

	y, mon, d, parse_ok := parse_openssl_enddate(string(stdout))
	if !parse_ok {
		return 0, false
	}

	now := time.now()
	ny, nm, nd := time.date(now)
	days = i32(days_from_civil(y, mon, d) - days_from_civil(ny, int(nm), nd))
	return days, true
}

// check_https shells out to curl for an HTTPS uptime + latency check (up = 2xx),
// keeping the up/down definition consistent with plain-HTTP targets. Impure.
check_https :: proc(target: Target) -> (up: bool, latency_seconds: f64) {
	_, stdout, stderr, err := os.process_exec(
		os.Process_Desc {
			command = []string {
				"curl", "-sS",
				"-o", "/dev/null",
				"-w", "%{http_code} %{time_total}",
				"--max-time", "5",
				target.url,
			},
		},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	if err != nil {
		return false, 0
	}

	fields := strings.fields(strings.trim_space(string(stdout))) // "200 0.234"
	defer delete(fields)
	if len(fields) < 2 {
		return false, 0
	}
	code, code_ok := strconv.parse_int(fields[0], 10)
	if !code_ok {
		return false, 0
	}
	latency_seconds, _ = strconv.parse_f64(fields[1])
	return is_up(code), latency_seconds
}


run_checks :: proc(targets: []Target, results: Results) {
	for target, i in targets {
		switch check_kind_for(target.url) {
		case .HTTP:
			up, latency := check_http(target)
			results.ups[i] = up
			results.latencies[i] = latency
			results.expiry_days[i] = NO_EXPIRY
		case .HTTPS:
			up, latency := check_https(target)
			results.ups[i] = up
			results.latencies[i] = latency
			if days, ok := cert_expiry_days(host_only(target.url)); ok {
				results.expiry_days[i] = days
			} else {
				results.expiry_days[i] = NO_EXPIRY
			}
		}
	}
}
