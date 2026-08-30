// Package migrations applies the SQL schema files alongside it.
//
// Nothing previously applied database/migrations at all — the files had to be
// pasted into psql by hand, which is why the deployed schema had drifted away
// from what the controllers query. The SQL is embedded so a compiled binary
// carries its own schema and needs no repo checkout to migrate.
package migrations

import (
	"database/sql"
	"embed"
	"fmt"
	"io/fs"
	"log"
	"sort"
	"strings"
)

//go:embed *.sql
var migrationFS embed.FS

// Run applies every unapplied migration in filename order, each in its own
// transaction, and records what ran in schema_migrations.
func Run(db *sql.DB) error {
	if db == nil {
		return fmt.Errorf("database is not connected")
	}

	if _, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version     TEXT PRIMARY KEY,
			applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)
	`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	applied := map[string]bool{}
	rows, err := db.Query(`SELECT version FROM schema_migrations`)
	if err != nil {
		return fmt.Errorf("read schema_migrations: %w", err)
	}
	for rows.Next() {
		var v string
		if err := rows.Scan(&v); err != nil {
			rows.Close()
			return err
		}
		applied[v] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	entries, err := fs.ReadDir(migrationFS, ".")
	if err != nil {
		return fmt.Errorf("read migrations: %w", err)
	}

	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			names = append(names, e.Name())
		}
	}
	// Filenames are zero-padded (001_, 002_, ...), so lexical order is
	// execution order.
	sort.Strings(names)

	ran := 0
	for _, name := range names {
		if applied[name] {
			continue
		}

		body, err := migrationFS.ReadFile(name)
		if err != nil {
			return fmt.Errorf("read %s: %w", name, err)
		}

		tx, err := db.Begin()
		if err != nil {
			return fmt.Errorf("begin %s: %w", name, err)
		}
		if _, err := tx.Exec(string(body)); err != nil {
			tx.Rollback()
			return fmt.Errorf("apply %s: %w", name, err)
		}
		if _, err := tx.Exec(
			`INSERT INTO schema_migrations (version) VALUES ($1)`, name); err != nil {
			tx.Rollback()
			return fmt.Errorf("record %s: %w", name, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("commit %s: %w", name, err)
		}

		log.Printf("[migrate] applied %s", name)
		ran++
	}

	if ran == 0 {
		log.Println("[migrate] schema is up to date")
	} else {
		log.Printf("[migrate] applied %d migration(s)", ran)
	}
	return nil
}

// List returns the embedded migration filenames in execution order. Exposed so
// a build-time check can confirm every .sql file was actually embedded — a
// missing //go:embed pattern fails silently at runtime otherwise.
func List() ([]string, error) {
	entries, err := fs.ReadDir(migrationFS, ".")
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names, nil
}
