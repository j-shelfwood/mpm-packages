# Influx Collector (CC:Tweaked)

Telemetry collector that publishes metrics to a self-hosted InfluxDB v2 instance.

## Install + Run
```
mpm install influx-collector
mpm run influx-collector
```

## Terminal Dashboard
The collector runs an event-driven terminal dashboard showing collection cadence, flush status, and peripheral counts.
- Triggered by `collector_event` or `collector_dirty` events
- Redraws at most once per second on a timer

## HTTP Notes
- If you see `http.checkURL blocked`, add `https://influx.shelfwood.co` to your CC:Tweaked HTTP whitelist.
- If you see `http.post failed`, the dashboard now surfaces the exact reason and status body.
- URL inputs must include `http://` or `https://` (invalid inputs are rejected at setup).

## Configuration
The collector reads config from three locations (lowest to highest priority):
1. `/influx-collector.config`
2. `/influx-collector.env`
3. `settings` API (`influx.collector.*`)

On first run it prompts for URL/org/bucket/token and writes all three.

### Env File Keys
```
INFLUX_URL=https://influx.shelfwood.co
INFLUX_ORG=shelfwood
INFLUX_BUCKET=mc
INFLUX_TOKEN=...token...
INFLUX_NODE=overworld-node
INFLUX_SHARE_TOKEN=false
```

### Settings Keys
- `influx.collector.url`
- `influx.collector.org`
- `influx.collector.bucket`
- `influx.collector.token`
- `influx.collector.node`

### Defaults
- `url`: https://influx.shelfwood.co
- `org`: shelfwood
- `bucket`: mc
- `node`: computer label or `cc-<id>`
- `share_token`: false
- `machine_interval_s`: 5
- `machine_burst_interval_s`: 1
- `machine_burst_window_s`: 10
- `energy_interval_s`: 5
- `energy_detector_interval_s`: 5
- `energy_detector_burst_interval_s`: 1
- `energy_detector_burst_window_s`: 10
- `ae_interval_s`: 60
- `ae_slow_interval_s`: 600
- `ae_slow_threshold_ms`: 5000
- `ae_top_items`: 20
- `ae_top_fluids`: 10
- `flush_interval_s`: 5
- `max_buffer_lines`: 5000

## Measurements
### `machine_activity`
Tags: `node`, `mod`, `category`, `type`, `name`  
Fields: `active`, `progress`, `progress_total`, `progress_percent`, `production_rate`, `energy_usage`, `energy_percent`, `formed`

### `energy_storage`
Tags: `node`, `mod`, `type`, `name`, `storage`  
Fields: `stored_fe`, `capacity_fe`, `percent`

### `energy_total`
Tags: `node`  
Fields: `stored_fe`, `capacity_fe`, `percent`

### `energy_flow`
Tags: `node`, `name`  
Fields: `rate_fe_t`, `limit_fe_t`

### `ae_summary`
Tags: `node`, `source`  
Fields: `items_total`, `items_unique`, `fluids_total`, `fluids_unique`, `item_storage_used`, `item_storage_total`, `item_storage_available`, `fluid_storage_used`, `fluid_storage_total`, `fluid_storage_available`, `energy_stored`, `energy_capacity`, `energy_usage`

### `ae_item`
Tags: `node`, `item`  
Fields: `count`

### `ae_fluid`
Tags: `node`, `fluid`  
Fields: `amount`

## Notes
- AE2 lists are limited to top N items/fluids to keep payloads bounded.
- Tokens are stored in plain text on the computer; use a least-privilege token per bucket.
- Burst polling auto-activates for machines and energy detectors when activity is detected, then decays after the burst window.
- Config sync: a new node broadcasts on `influx_collector_sync` and copies url/org/bucket, plus token only if `share_token=true` on the existing node.
- AE metrics are only emitted when the ME Bridge is connected; dashboard shows AE connection status.
