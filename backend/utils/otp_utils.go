package utils

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"math/big"
)

// GenerateOTP returns a uniformly random 6-digit code.
//
// The old implementation used math/rand seeded from the default source, which
// is deterministic and predictable, and `rand.Intn(999999)` could never emit
// 999999 — a small but real bias.
func GenerateOTP() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// HashOTP derives the value stored in the database. Codes are short-lived but
// storing them in clear text means a read-only leak of the otps table is a
// full account-takeover kit for every pending login.
func HashOTP(email, code string) string {
	sum := sha256.Sum256([]byte(email + ":" + code))
	return hex.EncodeToString(sum[:])
}

// CompareOTPHash compares two OTP hashes without leaking timing information.
func CompareOTPHash(a, b string) bool {
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}
