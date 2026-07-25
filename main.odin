package main

import "core:fmt"
import "core:os"

CONFIG_PATH :: "config.json"

main :: proc() {
	config, ok := load_config(CONFIG_PATH)
	if !ok {
		fmt.eprintfln("error: failed to load config from %q", CONFIG_PATH)
		os.exit(1)
	}
	defer delete_config(config)

	fmt.printfln("loaded %d target(s) from %s:", len(config.targets), CONFIG_PATH)
	for target, i in config.targets {
		kind := check_kind_for(target.url)
		fmt.printfln("  [%d] %-10s %-45s -> %v", i, target.name, target.url, kind)
	}

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
	// Run one check cycle now. HTTPS targets are stubbed until the TLS path lands.
	run_checks(config.targets, results)

	metrics := metrics_to_string(config.targets, results)
	defer delete(metrics)
	fmt.println("\n--- /metrics ---")
	fmt.print(metrics)
}
