# Architecture diagrams

Mermaid diagrams of GPS PARA EL CIELO as the code stands on 2026-11-24. Anything not live in production is marked **OFF**, **LOCAL ONLY**, **NOT RUN** or **planned**. Update the matching diagram whenever the code changes (see the master blueprint).

| # | Diagram | Main code |
|---|---|---|
| 1 | [Application architecture](01_application_architecture.md) | `functions/src/index.js`, `lib/core/data/*` |
| 2 | [Signup and authentication](02_signup_authentication.md) | `auth_controller.dart`, `auth_service.dart` |
| 3 | [Primary location onboarding](03_primary_location_onboarding.md) | `location_setup_controller.dart`, `firestore.rules`, `src/location.js` |
| 4 | [Cache-first discovery](04_cache_first_discovery.md) | `src/owners.js` `discoverOwners` |
| 5 | [Overlap cache reuse](05_overlap_cache_reuse.md) | `src/property_cache.js` |
| 6 | [Firestore data model](06_firestore_data_model.md) | `firestore.rules`, `firestore_paths.dart` |
| 7 | [Credit accounting](07_credit_accounting.md) | `reserveOwners`, `src/budget.js` |
| 8 | [Discovery locking](08_discovery_locking.md) | `acquireLease` … `finishLease` |
| 9 | [Prayer List lifecycle](09_prayer_list_lifecycle.md) | `household_store.dart`, `prayer_list_service.dart` |
| 10 | [Household identity](10_household_identity.md) | `OwnerOverlayArea`, `src/cleanup.js` |
| 11 | [App Check and authorization](11_app_check_authorization.md) | `index.js`, `owners.js`, rules |
| 12 | [Failure and recovery](12_failure_recovery.md) | `owners.js`, `owner_discovery.dart` |
| 13 | [Expiry and refresh](13_expiry_refresh.md) | `property_cache.js`, `tool/migrate_cache_ttl.js` |
| 14 | [Production deployment](14_production_deployment.md) | `tool/deploy_blueprint.sh` |
| 15 | [Monitoring and incidents](15_monitoring_incident.md) | `tool/melissa_ops.js` |

## Rendering and validation

All 26 Mermaid blocks (25 in the 15 diagram files + 1 in `APP_FLOW.md`)
render without errors with mermaid-cli 11.4.2 (validated 2026-11-24).
The SVGs are in [rendered/](rendered/). Re-render and re-validate after any
edit with `tool/render_diagrams.sh`, which stops at the first syntax error.
