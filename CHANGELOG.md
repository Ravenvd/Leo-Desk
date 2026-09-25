# Changelog

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
