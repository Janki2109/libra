package utils

import "regexp"

// indianMobileRe matches a 10-digit Indian mobile number starting with 6-9,
// with no spaces, letters, or punctuation.
var indianMobileRe = regexp.MustCompile(`^[6-9]\d{9}$`)

// ValidPhone reports whether phone is a valid 10-digit Indian mobile number.
// Callers should trim the input before storing it; this only validates.
func ValidPhone(phone string) bool {
	return indianMobileRe.MatchString(phone)
}
