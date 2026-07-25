package main

import "core:fmt"
import "core:strings"


Results :: struct {
	ups:         []bool, // up=true / down=false
	latencies:   []f64,  // seconds
	expiry_days: []i32,  // days until TLS cert expiry; NO_EXPIRY for HTTP targets
}

// NO_EXPIRY marks a target with no TLS cert (plain HTTP); its cert line is omitted.
NO_EXPIRY :: i32(-1)

METRIC_UP          :: "healthcheck_up"
METRIC_RESPONSE    :: "healthcheck_response_seconds"
METRIC_CERT_EXPIRY :: "healthcheck_cert_expiry_days"

// write_help_type emits the "# HELP" and "# TYPE" preamble for one metric.
write_help_type :: proc(b: ^strings.Builder, name, help: string) {
	strings.write_string(b, "# HELP ")
	strings.write_string(b, name)
	strings.write_byte(b, ' ')
	strings.write_string(b, help)
	strings.write_string(b, "\n# TYPE ")
	strings.write_string(b, name)
	strings.write_string(b, " gauge\n")
}

// write_label_line writes the metric name + {target="..."} label + trailing space,
write_label_line :: #force_inline proc(b: ^strings.Builder, name, target: string) {
	strings.write_string(b, name)
	strings.write_string(b, `{target="`)
	strings.write_string(b, target)
	strings.write_string(b, `"} `)
}

// write_metrics renders all metrics for the given targets/results into b in
// Prometheus exposition text format. Metrics are grouped (each HELP/TYPE once,
// followed by all its series) per Prometheus conventions.
write_metrics :: proc(b: ^strings.Builder, targets: []Target, r: Results) {
	write_help_type(b, METRIC_UP, "Whether the target is up (1) or down (0).")
	for target, i in targets {
		write_label_line(b, METRIC_UP, target.name)
		strings.write_string(b, r.ups[i] ? "1" : "0")
		strings.write_byte(b, '\n')
	}

	write_help_type(b, METRIC_RESPONSE, "Response time of the last check in seconds.")
	for target, i in targets {
		write_label_line(b, METRIC_RESPONSE, target.name)
		fmt.sbprintf(b, "%.6f", r.latencies[i])
		strings.write_byte(b, '\n')
	}

	write_help_type(b, METRIC_CERT_EXPIRY, "Days until the TLS certificate expires (HTTPS only).")
	for target, i in targets {
		if r.expiry_days[i] == NO_EXPIRY {
			continue
		}
		write_label_line(b, METRIC_CERT_EXPIRY, target.name)
		fmt.sbprintf(b, "%d", r.expiry_days[i])
		strings.write_byte(b, '\n')
	}
}

// Builds the full exposition into a fresh buffer and 
// returns it as a string. The caller owns the result (delete it).
metrics_to_string :: proc(targets: []Target, r: Results, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	write_metrics(&b, targets, r)
	return strings.to_string(b)
}
