package main

import "core:testing"

@(test)
test_parse_config_ok :: proc(t: ^testing.T) {
	data := `{
		"targets": [
			{ "name": "blog", "url": "https://ramareksotinoyo.my.id" },
			{ "name": "grafana", "url": "http://localhost:3000/api/health" }
		]
	}`
	config, err := parse_config(transmute([]byte)data)
	defer delete_config(config)

	testing.expect(t, err == nil, "expected no parse error")
	testing.expect_value(t, len(config.targets), 2)
	testing.expect_value(t, config.targets[0].name, "blog")
	testing.expect_value(t, config.targets[0].url, "https://ramareksotinoyo.my.id")
	testing.expect_value(t, config.targets[1].name, "grafana")
}

@(test)
test_parse_config_empty_targets :: proc(t: ^testing.T) {
	data := `{ "targets": [] }`
	config, err := parse_config(transmute([]byte)data)
	defer delete_config(config)

	testing.expect(t, err == nil, "expected no parse error")
	testing.expect_value(t, len(config.targets), 0)
}

@(test)
test_check_kind_for :: proc(t: ^testing.T) {
	testing.expect_value(t, check_kind_for("https://ramareksotinoyo.my.id"), Check_Kind.HTTPS)
	testing.expect_value(t, check_kind_for("http://localhost:3000/api/health"), Check_Kind.HTTP)
	testing.expect_value(t, check_kind_for("http://localhost:9000/minio/health/live"), Check_Kind.HTTP)
}
