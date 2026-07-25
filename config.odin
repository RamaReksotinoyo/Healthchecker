package main

import "core:encoding/json"
import "core:os"
import "core:strings"


// Check loop can switch on it and let the compiler inline the branch
Check_Kind :: enum {
	HTTP,
	HTTPS,
}

// Target as loaded from config.json
Target :: struct {
	name: string,
	url:  string,
}

Config :: struct {
	targets: []Target,
}

// check_kind_for decides the check type purely from the URL scheme. Only HTTPS
// targets get a TLS cert-expiry check; HTTP targets are uptime/latency only.
check_kind_for :: proc(url: string) -> Check_Kind {
	if strings.has_prefix(url, "https://") {
		return .HTTPS
	}
	return .HTTP
}

parse_config :: proc(data: []byte) -> (Config, json.Unmarshal_Error) {
	config: Config
	err := json.unmarshal(data, &config)
	return config, err
}

load_config :: proc(path: string) -> (Config, bool) {
	data, read_err := os.read_entire_file_from_path(path, context.allocator)
	if read_err != nil {
		return {}, false
	}
	defer delete(data)

	config, err := parse_config(data)
	if err != nil {
		return {}, false
	}
	return config, true
}

delete_config :: proc(config: Config) {
	for target in config.targets {
		delete(target.name)
		delete(target.url)
	}
	delete(config.targets)
}
