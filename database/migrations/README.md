# Migrations moved

The SQL migration files now live in [`backend/migrations/`](../../backend/migrations/).

They were moved so the Go server can embed them (`//go:embed *.sql`) and apply
them itself on startup — Go's `embed` cannot reach outside its own package
directory. Previously nothing ran these files at all; they had to be pasted
into `psql` by hand, which is how the deployed schema drifted away from what the
controllers query.

## Applying them

The server runs any unapplied migration automatically at boot and records what
it ran in the `schema_migrations` table. To skip that (for example when a
migration should be applied by a separate deploy step):

```
RUN_MIGRATIONS=false
```

To apply them by hand instead:

```sh
for f in backend/migrations/*.sql; do psql "$DATABASE_URL" -f "$f"; done
psql "$DATABASE_URL" -f database/seeds/seed_roles.sql
```
