package main

import "core:testing"

@(test)
test_write_metrics_exact :: proc(t: ^testing.T) {
	targets := []Target {
		{name = "blog", url = "https://example.com"},
		{name = "grafana", url = "http://localhost:3000/api/health"},
		{name = "minio", url = "http://localhost:9000/minio/health/live"},
	}
	results := Results {
		ups         = []bool{true, true, false},
		latencies   = []f64{0.123, 0.008, 0.0},
		expiry_days = []i32{42, NO_EXPIRY, NO_EXPIRY},
	}

	got := metrics_to_string(targets, results)
	defer delete(got)

	expected := `# HELP healthcheck_up Whether the target is up (1) or down (0).
# TYPE healthcheck_up gauge
healthcheck_up{target="blog"} 1
healthcheck_up{target="grafana"} 1
healthcheck_up{target="minio"} 0
# HELP healthcheck_response_seconds Response time of the last check in seconds.
# TYPE healthcheck_response_seconds gauge
healthcheck_response_seconds{target="blog"} 0.123000
healthcheck_response_seconds{target="grafana"} 0.008000
healthcheck_response_seconds{target="minio"} 0.000000
# HELP healthcheck_cert_expiry_days Days until the TLS certificate expires (HTTPS only).
# TYPE healthcheck_cert_expiry_days gauge
healthcheck_cert_expiry_days{target="blog"} 42
`
	testing.expect_value(t, got, expected)
}

// A target list with no HTTPS targets should produce no cert-expiry series (only
// the HELP/TYPE preamble for that metric).
@(test)
test_write_metrics_no_https :: proc(t: ^testing.T) {
	targets := []Target{{name = "grafana", url = "http://localhost:3000/api/health"}}
	results := Results {
		ups         = []bool{true},
		latencies   = []f64{0.005},
		expiry_days = []i32{NO_EXPIRY},
	}

	got := metrics_to_string(targets, results)
	defer delete(got)

	expected := `# HELP healthcheck_up Whether the target is up (1) or down (0).
# TYPE healthcheck_up gauge
healthcheck_up{target="grafana"} 1
# HELP healthcheck_response_seconds Response time of the last check in seconds.
# TYPE healthcheck_response_seconds gauge
healthcheck_response_seconds{target="grafana"} 0.005000
# HELP healthcheck_cert_expiry_days Days until the TLS certificate expires (HTTPS only).
# TYPE healthcheck_cert_expiry_days gauge
`
	testing.expect_value(t, got, expected)
}
