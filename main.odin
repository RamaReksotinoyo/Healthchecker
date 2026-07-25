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
}
