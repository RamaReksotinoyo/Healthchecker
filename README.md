# Odin Healthcheck

A lightweight uptime + TLS certificate-expiry monitoring daemon written in
[Odin](https://odin-lang.org/). It checks a list of HTTP(S) targets on an
interval and exposes the results in [Prometheus](https://prometheus.io/)
exposition format on a `/metrics` endpoint, ready to be scraped by an existing
Prometheus/Grafana stack.

## Features

- **Multi-target checks** — targets loaded from a JSON config file, no hardcoding.
- **HTTP status check** — a target is *up* on `2xx`, *down* on timeout / `5xx` /
  connection refused.
- **Response-time recording** — latency captured per check.
- **TLS cert-expiry check** — days-until-expiry read from the TLS handshake for
  each HTTPS target.
- **`/metrics` endpoint** — results exposed in Prometheus text format.

> **Status:** early development. Config loading is implemented and tested; the
> check loop, `/metrics` server, and TLS check are being built incrementally.
