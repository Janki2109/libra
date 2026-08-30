package models

import "time"

type User struct {
	ID               string     `json:"id" db:"id"`
	Name             string     `json:"name" db:"name"`
	Email            string     `json:"email" db:"email"`
	Phone            string     `json:"phone" db:"phone"`
	PasswordHash     string     `json:"-" db:"password_hash"`
	RoleID           string     `json:"role_id" db:"role_id"`
	RoleName         string     `json:"role_name" db:"role_name"`
	FirmID           string     `json:"firm_id" db:"firm_id"`
	AvatarURL        string     `json:"avatar_url" db:"avatar_url"`
	BarCouncilNumber string     `json:"bar_council_number" db:"bar_council_number"`
	Designation      string     `json:"designation" db:"designation"`
	IsActive         bool       `json:"is_active" db:"is_active"`
	EmailVerified    bool       `json:"email_verified" db:"email_verified"`
	LastLoginAt      *time.Time `json:"last_login_at" db:"last_login_at"`
	CreatedAt        time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at" db:"updated_at"`
}

type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
}

type RegisterRequest struct {
	Name     string `json:"name" binding:"required"`
	Email    string `json:"email" binding:"required,email"`
	Phone    string `json:"phone"`
	Password string `json:"password" binding:"required,min=6"`
	Role     string `json:"role"`
	FirmID   string `json:"firm_id"`
}

type OTPRequest struct {
	Email string `json:"email" binding:"required,email"`
}

type VerifyOTPRequest struct {
	Email string `json:"email" binding:"required,email"`
	OTP   string `json:"otp" binding:"required"`
}

type ChangePasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=6"`
}

type AuthResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}
