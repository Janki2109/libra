package utils

import (
	"errors"
	"libra/config"
	"log"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// DefaultJWTSecret is the value the repo shipped with. It must never be used
// by a production deployment, so startup refuses to boot on it.
const DefaultJWTSecret = "libra_law_super_secret_key_2024"

type Claims struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
	Role   string `json:"role"`
	FirmID string `json:"firm_id"`
	jwt.RegisteredClaims
}

func jwtSecret() []byte {
	return []byte(config.GetEnv("JWT_SECRET", "libra_secret"))
}

// tokenTTL honours JWT_EXPIRY (e.g. "24h", "30m"). The old code accepted the
// variable in .env but hardcoded 24h, so shortening session lifetime silently
// did nothing.
func tokenTTL() time.Duration {
	raw := config.GetEnv("JWT_EXPIRY", "24h")
	d, err := time.ParseDuration(raw)
	if err != nil || d <= 0 {
		log.Printf("[jwt] invalid JWT_EXPIRY %q, falling back to 24h", raw)
		return 24 * time.Hour
	}
	return d
}

func GenerateToken(userID, email, role, firmID string) (string, error) {
	if userID == "" {
		// Guards against handlers that scan a user row into zero values and
		// then mint a token for "" — an unauthenticated session that would
		// still pass the auth middleware.
		return "", errors.New("refusing to issue token without a user id")
	}

	now := time.Now()
	claims := Claims{
		UserID: userID,
		Email:  email,
		Role:   role,
		FirmID: firmID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL())),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			Issuer:    "libra-law",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(jwtSecret())
}

func ValidateToken(tokenStr string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(
		tokenStr,
		&Claims{},
		func(t *jwt.Token) (interface{}, error) { return jwtSecret(), nil },
		// Pin the algorithm so a token that claims a different `alg` can never
		// reach the HMAC key.
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer("libra-law"),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}
	if claims.UserID == "" {
		return nil, errors.New("token carries no user id")
	}

	return claims, nil
}
