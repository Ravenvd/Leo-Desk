# Changelog

## 1.3.0 - 2026-10-31

### Added
- Staff Manager with staff profiles, manual full-day/half-day/absent/leave attendance, check-in/check-out records, and automatic overtime pay before 10 AM and after 4 PM.
- Monthly payroll summaries with separate earned, paid, and outstanding balances, plus payment history. Recording a staff payment automatically creates a linked Salaries expense.
- Staff, attendance, and payroll payment records included in Android–Windows LAN sync.

### Fixed
- Resolve duplicate bills for the same order by keeping the earliest-created bill, with UUID as a deterministic tie-breaker.
- Replace losing bill records and line items atomically during sync.
- Reject bill-number collisions across different orders without deleting unrelated data.
- Add regression tests for bill conflict resolution and line-item preservation.

## 1.2.0 - 2026-09-25

### Added
- Embroidery and Aari cost calculator with machine-time pricing.
- Bulk quantity discounts and stitch-based designer fees.
- Persisted monthly EB and rent inputs for calculator pricing.
- Business revenue target and revenue-rate checker.
- Aari-specific machine speed and pricing adjustments.

### Changed
- Refined customer records by removing redundant Customer Type and Service Required fields.
- Added database migration from schema v11 to v12 while preserving customer, order, invoice, and bill relationships.
- Updated calculator pricing to use operating costs, overhead buffer, and profit markup.
- Updated branding and application presentation for the Leo Stitch & Design workflow.
