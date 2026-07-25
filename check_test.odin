package main

import "core:testing"

@(test)
test_is_up :: proc(t: ^testing.T) {
	testing.expect(t, is_up(200), "200 should be up")
	testing.expect(t, is_up(204), "204 should be up")
	testing.expect(t, is_up(299), "299 should be up")
	testing.expect(t, !is_up(199), "199 should be down")
	testing.expect(t, !is_up(301), "301 should be down")
	testing.expect(t, !is_up(404), "404 should be down")
	testing.expect(t, !is_up(500), "500 should be down")
	testing.expect(t, !is_up(503), "503 should be down")
}

@(test)
test_parse_status_code :: proc(t: ^testing.T) {
	code, ok := parse_status_code("HTTP/1.1 200 OK")
	testing.expect(t, ok, "valid line should parse")
	testing.expect_value(t, code, 200)

	code2, ok2 := parse_status_code("HTTP/1.0 503 Service Unavailable")
	testing.expect(t, ok2, "valid line should parse")
	testing.expect_value(t, code2, 503)

	_, ok3 := parse_status_code("garbage line without http prefix")
	testing.expect(t, !ok3, "non-HTTP line should fail")

	_, ok4 := parse_status_code("")
	testing.expect(t, !ok4, "empty line should fail")

	_, ok5 := parse_status_code("HTTP/1.1")
	testing.expect(t, !ok5, "line with no code should fail")
}
