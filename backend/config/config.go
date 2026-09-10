package config

import (
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

func LoadConfig() {
	err := godotenv.Load()
	if err != nil {
		log.Println("No .env file found, using system environment variables")
	}
	log.Println("✅ Config loaded")
}

func GetEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

// IsProduction reports whether production hardening is on.
func IsProduction() bool {
	env := strings.ToLower(GetEnv("APP_ENV", GetEnv("ENV", "development")))
	return env == "production" || env == "prod"
}

// Validate refuses to start a production process that is misconfigured in a way
// that would be a security problem.
//
// The repository ships a .env with a known JWT secret and placeholder AWS and
// SMTP credentials. Deploying it as-is means every token the service issues can
// be forged by anyone who has read the repo — so the process must refuse to
// come up in that state rather than come up and look healthy.
func Validate() error {
	var problems []string

	secret := GetEnv("JWT_SECRET", "")
	switch {
	case secret == "":
		problems = append(problems, "JWT_SECRET is not set")
	case secret == "libra_law_super_secret_key_2024" || secret == "libra_secret":
		problems = append(problems,
			"JWT_SECRET is still the value committed to the repository — generate a new one "+
				"(openssl rand -base64 48)")
	case len(secret) < 32:
		problems = append(problems, "JWT_SECRET is shorter than 32 characters")
	}

	if GetEnv("DB_PASSWORD", "") == "" && GetEnv("DATABASE_URL", "") == "" {
		problems = append(problems, "DB_PASSWORD (or DATABASE_URL) is not set")
	}
	if GetEnv("DB_SSLMODE", "disable") == "disable" && GetEnv("DATABASE_URL", "") == "" {
		problems = append(problems,
			"DB_SSLMODE is 'disable' — case files and client records would travel unencrypted; "+
				"use 'require' or stronger")
	}

	// A production deploy pointed at a loopback address is always wrong — it
	// means the managed database's connection details (e.g. Render's
	// PostgreSQL "Internal Database URL") were never actually set, and the
	// process fell back to config.go's local-dev defaults instead. That used
	// to surface only once ConnectDatabase tried to dial it and Postgres's own
	// driver produced a bare "connection refused", with nothing pointing at
	// the actual cause — refuse to start instead, with a message that names
	// the real fix.
	if IsProduction() {
		if dbURL := GetEnv("DATABASE_URL", ""); dbURL != "" {
			if strings.Contains(dbURL, "127.0.0.1") || strings.Contains(dbURL, "localhost") {
				problems = append(problems,
					"DATABASE_URL points at localhost/127.0.0.1 in production — use your managed "+
						"PostgreSQL service's own connection string (e.g. Render's Internal or "+
						"External Database URL for the 'libra database' service), not a local database")
			}
		} else {
			switch GetEnv("DB_HOST", "localhost") {
			case "localhost", "127.0.0.1", "::1":
				problems = append(problems,
					"DB_HOST resolves to localhost in production — set DATABASE_URL, or "+
						"DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME, to your managed PostgreSQL "+
						"service's own connection details (e.g. Render's 'libra database' service), "+
						"not a local database")
			}
		}
	}

	if GetEnv("CORS_ORIGINS", "") == "" {
		log.Println("[config] CORS_ORIGINS is empty — browser clients will be refused " +
			"(fine for a mobile-only API)")
	}

	// Payment and mail are optional, but half-configured is worse than absent:
	// it fails at the moment a customer is trying to pay or sign in.
	keyID := GetEnv("RAZORPAY_KEY_ID", "")
	keySecret := GetEnv("RAZORPAY_KEY_SECRET", "")
	if (keyID == "") != (keySecret == "") {
		problems = append(problems,
			"RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET must be set together")
	}
	if keyID == "" {
		log.Println("[config] Razorpay is not configured — online payment endpoints will return 503")
	} else if GetEnv("RAZORPAY_WEBHOOK_SECRET", "") == "" {
		// The webhook is the authoritative activation path: a user who kills
		// the app right after paying never reaches the client callback. Taking
		// payments without it means charging cards and not granting the plan.
		problems = append(problems,
			"RAZORPAY_WEBHOOK_SECRET is not set — payments would be taken but "+
				"subscriptions would not activate when a user closes the app mid-checkout")
	}

	smtpUser := GetEnv("SMTP_USER", "")
	if smtpUser == "" || strings.Contains(smtpUser, "your_email") {
		problems = append(problems,
			"SMTP_USER/SMTP_PASS are unset or still placeholders — verification codes and "+
				"portal invitations cannot be delivered")
	}

	if len(problems) == 0 {
		return nil
	}

	if !IsProduction() {
		for _, p := range problems {
			log.Printf("[config] warning: %s", p)
		}
		return nil
	}

	return fmt.Errorf("refusing to start in production:\n  - %s",
		strings.Join(problems, "\n  - "))
}
