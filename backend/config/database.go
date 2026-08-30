package config

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"time"

	_ "github.com/lib/pq"
)

var DB *sql.DB

// ConnectDatabase opens the pool and verifies it is reachable.
func ConnectDatabase() {
	dsn := GetEnv("DATABASE_URL", "")
	if dsn == "" {
		// Password and DSN are never logged: a connection failure used to print
		// the driver's error, which on some Postgres builds echoes the DSN.
		dsn = fmt.Sprintf(
			"host=%s port=%s user=%s password=%s dbname=%s sslmode=%s connect_timeout=10",
			GetEnv("DB_HOST", "localhost"),
			GetEnv("DB_PORT", "5432"),
			GetEnv("DB_USER", "postgres"),
			GetEnv("DB_PASSWORD", "postgres"),
			GetEnv("DB_NAME", "libra_law"),
			GetEnv("DB_SSLMODE", "disable"),
		)
	}

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatal("❌ Failed to open database: ", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		log.Fatal("❌ Database ping failed: ", err)
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	// Without these two, pooled connections live forever. Managed Postgres
	// (Render, RDS, Supabase) recycles idle server-side connections, and the
	// pool then hands out sockets the server has already closed — which
	// surfaces as sporadic "driver: bad connection" 500s under low traffic.
	db.SetConnMaxLifetime(30 * time.Minute)
	db.SetConnMaxIdleTime(5 * time.Minute)

	DB = db
	log.Println("✅ Database connected successfully")
}

// Healthy reports whether the pool can still reach Postgres. The /health
// endpoint used to answer 200 unconditionally, so a load balancer kept routing
// traffic to an instance whose database was gone.
func Healthy(ctx context.Context) error {
	if DB == nil {
		return fmt.Errorf("database is not connected")
	}
	return DB.PingContext(ctx)
}
