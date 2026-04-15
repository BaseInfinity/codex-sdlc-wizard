#!/bin/bash
# Domain-specific testing sections for TESTING.md template
# Sourced by setup.sh — provides get_domain_section()

get_domain_section() {
    local domain="$1"
    case "$domain" in
        firmware)
            cat <<'SECTION'
## Firmware-Specific Testing

| Layer | Purpose | Example |
|-------|---------|---------|
| SIL (Software-in-Loop) | Logic without hardware | Mock GPIO, test state machines |
| HIL (Hardware-in-Loop) | Real hardware targets | Flash and verify on device |
| Config validation | Multi-device configs | Validate all .cfg files parse correctly |

- Test without hardware first (SIL), then validate on real targets (HIL)
- Each device config gets its own validation test
- Flash/burn operations need rollback verification
SECTION
            ;;
        data-science)
            cat <<'SECTION'
## Data Science-Specific Testing

| Layer | Purpose | Example |
|-------|---------|---------|
| Data validation | Input integrity | Schema checks, null handling, dtype verification |
| Pipeline | Transform correctness | Known input → expected output |
| Model evaluation | Performance metrics | Accuracy/F1 above threshold on hold-out set |

- Pin random seeds for reproducibility
- Test data transforms independently from model training
- Use small fixture datasets, not production data
SECTION
            ;;
        cli)
            cat <<'SECTION'
## CLI-Specific Testing

| Layer | Purpose | Example |
|-------|---------|---------|
| Unit | Flag parsing, output formatting | Test each subcommand's options |
| Integration | Command execution end-to-end | Run CLI with args, check stdout/exit code |
| Error paths | Bad input, missing files | Verify helpful error messages and non-zero exit |

- Test stdout and stderr separately
- Verify exit codes (0 for success, non-zero for errors)
- Test with pipes and redirects where relevant
SECTION
            ;;
        *)
            cat <<'SECTION'
## Web-Specific Testing

| Layer | Purpose | Example |
|-------|---------|---------|
| Unit | Pure logic, utilities | Validators, formatters, calculations |
| Integration | API routes, database queries | Real DB, real HTTP, mock external services |
| E2E | Critical user flows | Login, checkout, data export |

- Test API contracts (request/response shapes)
- Use real databases in integration tests, not mocks
- E2E tests cover the happy path — edge cases belong in integration/unit
SECTION
            ;;
    esac
}
