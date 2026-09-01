# RCA 0003 — RDS creation failed: reserved database name

- **Date:** 2026-09-01
- **Severity:** Low — blocked the first RDS `apply`; caught before any dependent work
- **Status:** Resolved

## Context

The `modules/data` module created an `aws_db_instance` with
`db_name = "catalog"`.

## Impact

`terraform apply` failed:

```
Error: creating RDS DB Instance (ce-capstone-pg): InvalidParameterValue:
DBName catalog cannot be used. It is a reserved word for this engine
```

The RDS instance was not created; the launch template and other resources in the
same apply *were* created, leaving a partial apply to re-run.

## Root cause

`catalog` is on Amazon RDS's reserved-words list for the PostgreSQL engine.
This list is RDS-specific and larger than PostgreSQL's own reserved words, so it
is easy to hit without warning.

## Resolution

Renamed `db_name` to `cloudcart` (which also matches the local
`docker-compose.yml` database name, removing an inconsistency). The application
reads the database name from the `/ce-capstone/db/name` SSM parameter, which is
populated from `aws_db_instance.this.db_name`, so no application change was
needed. Re-ran `terraform apply`; RDS created successfully.

## Prevention / follow-up

- Check identifiers (DB name, master username) against the
  [RDS reserved words](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
  list, not just the engine's own reserved words.
- Prefer product-specific names (`cloudcart`) over generic ones (`catalog`,
  `admin`, `data`) that are more likely to be reserved.
