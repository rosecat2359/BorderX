// SQLite 数据库连接、迁移与 WAL 模式配置。
package store

import (
	"database/sql"
	"embed"
	"fmt"
	"os"
	"sort"
	"strings"

	_ "modernc.org/sqlite"
)

//go:embed migrations/*.sql
var migrations embed.FS

// Connect opens a SQLite database at dataSource and applies WAL / FK pragmas.
func Connect(dataSource string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", dataSource)
	if err != nil {
		return nil, err
	}

	// SQLite only supports a single writer at a time.
	db.SetMaxOpenConns(1)

	pragmas := []string{
		"PRAGMA journal_mode=WAL",
		"PRAGMA busy_timeout=5000",
		"PRAGMA foreign_keys=ON",
	}
	for _, p := range pragmas {
		if _, err := db.Exec(p); err != nil {
			return nil, fmt.Errorf("pragma %s: %w", p, err)
		}
	}

	return db, nil
}

// Migrate runs all *.sql files from the migrations directory in lexicographic order.
func Migrate(db *sql.DB) error {
	entries, err := migrations.ReadDir("migrations")
	if err != nil {
		return fmt.Errorf("read migration directory: %w", err)
	}

	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Name() < entries[j].Name()
	})

	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".sql") {
			continue
		}

		content, err := migrations.ReadFile("migrations/" + entry.Name())
		if err != nil {
			return fmt.Errorf("read %s: %w", entry.Name(), err)
		}

		if _, err := db.Exec(string(content)); err != nil {
			return fmt.Errorf("exec %s: %w", entry.Name(), err)
		}

		fmt.Fprintf(os.Stderr, "[migrate] %s OK\n", entry.Name())
	}

	return nil
}
