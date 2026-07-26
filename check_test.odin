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

@(test)
test_parse_openssl_enddate :: proc(t: ^testing.T) {
	// Note the double space before a single-digit day.
	y, m, d, ok := parse_openssl_enddate("notAfter=Sep  9 18:54:50 2026 GMT")
	testing.expect(t, ok, "valid enddate should parse")
	testing.expect_value(t, y, 2026)
	testing.expect_value(t, m, 9)
	testing.expect_value(t, d, 9)

	// Trailing newline (as captured from a pipe) and two-digit day.
	y2, m2, d2, ok2 := parse_openssl_enddate("notAfter=Jan 15 00:00:00 2027 GMT\n")
	testing.expect(t, ok2, "valid enddate with newline should parse")
	testing.expect_value(t, y2, 2027)
	testing.expect_value(t, m2, 1)
	testing.expect_value(t, d2, 15)

	_, _, _, ok3 := parse_openssl_enddate("garbage")
	testing.expect(t, !ok3, "garbage should fail")
}

@(test)
test_days_from_civil :: proc(t: ^testing.T) {
	testing.expect_value(t, days_from_civil(1970, 1, 1), i64(0))
	testing.expect_value(t, days_from_civil(1970, 1, 2), i64(1))
	testing.expect_value(t, days_from_civil(2000, 1, 1), i64(10957))

	// 25 Jul 2026 -> 9 Sep 2026 is 46 days (blog's cert).
	span := days_from_civil(2026, 9, 9) - days_from_civil(2026, 7, 25)
	testing.expect_value(t, span, i64(46))
}

@(test)
test_parse_openssl_enddate_errors :: proc(t: ^testing.T) {
	// Well-formed structure but invalid month name -> month lookup fails.
	_, _, _, ok1 := parse_openssl_enddate("notAfter=Xyz  9 18:54:50 2026 GMT")
	testing.expect(t, !ok1, "invalid month should fail")

	// Non-numeric day.
	_, _, _, ok2 := parse_openssl_enddate("notAfter=Sep XX 18:54:50 2026 GMT")
	testing.expect(t, !ok2, "non-numeric day should fail")

	// Non-numeric year.
	_, _, _, ok3 := parse_openssl_enddate("notAfter=Sep  9 18:54:50 YEAR GMT")
	testing.expect(t, !ok3, "non-numeric year should fail")

	// Too few fields.
	_, _, _, ok4 := parse_openssl_enddate("notAfter=Sep 9")
	testing.expect(t, !ok4, "too few fields should fail")
}

@(test)
test_month_from_abbrev :: proc(t: ^testing.T) {
	names := [12]string {
		"Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
	}
	for name, i in names {
		got, ok := month_from_abbrev(name)
		testing.expect(t, ok, "known month should resolve")
		testing.expect_value(t, got, i + 1)
	}

	_, ok_bad := month_from_abbrev("Foo")
	testing.expect(t, !ok_bad, "unknown month should fail")
	_, ok_empty := month_from_abbrev("")
	testing.expect(t, !ok_empty, "empty month should fail")
}

@(test)
test_host_only :: proc(t: ^testing.T) {
	testing.expect_value(t, host_only("https://example.com"), "example.com")
	testing.expect_value(t, host_only("http://localhost:3000/api/health"), "localhost")
	testing.expect_value(t, host_only("https://example.com:8443/path"), "example.com")
}
