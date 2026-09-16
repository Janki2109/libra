package services

import (
	"errors"
	"fmt"
	"libra/config"
	"log"
	"net"
	"net/smtp"
	"strings"
)

// ErrMailNotConfigured is returned when SMTP credentials are absent.
var ErrMailNotConfigured = errors.New("smtp is not configured")

// Mailer sends transactional email over SMTP.
//
// The API previously had no delivery path at all, which is why SendOTP handed
// the code back in its own JSON response — meaning anyone could request a code
// for any address and read it straight off the wire. Delivery has to exist
// before that response can be closed off.
type Mailer struct {
	host     string
	port     string
	user     string
	pass     string
	from     string
	fromName string
}

func NewMailer() *Mailer {
	// Some hosts (e.g. Render) default their SMTP integration to
	// SMTP_USERNAME/SMTP_PASSWORD rather than this codebase's original
	// SMTP_USER/SMTP_PASS — accept either so deployment env vars don't have
	// to be renamed to match the code.
	user := config.GetEnvAny("", "SMTP_USER", "SMTP_USERNAME")
	return &Mailer{
		host:     config.GetEnv("SMTP_HOST", ""),
		port:     config.GetEnv("SMTP_PORT", "587"),
		user:     user,
		pass:     config.GetEnvAny("", "SMTP_PASS", "SMTP_PASSWORD"),
		from:     config.GetEnvAny(user, "SMTP_FROM"),
		fromName: config.GetEnv("SMTP_FROM_NAME", "Libra Law"),
	}
}

// Configured reports whether the mailer can actually deliver.
func (m *Mailer) Configured() bool {
	return m.host != "" && m.user != "" && m.pass != "" && m.from != ""
}

// Send delivers a plain-text email. It never returns the message body to the
// caller and never logs the body, so secrets such as OTP codes stay out of
// application logs.
func (m *Mailer) Send(to, subject, body string) error {
	if !m.Configured() {
		return ErrMailNotConfigured
	}

	headers := map[string]string{
		"From":         fmt.Sprintf("%s <%s>", m.fromName, m.from),
		"To":           to,
		"Subject":      subject,
		"MIME-Version": "1.0",
		"Content-Type": `text/plain; charset="utf-8"`,
	}

	var msg strings.Builder
	for k, v := range headers {
		fmt.Fprintf(&msg, "%s: %s\r\n", k, v)
	}
	msg.WriteString("\r\n")
	msg.WriteString(body)

	auth := smtp.PlainAuth("", m.user, m.pass, m.host)
	addr := net.JoinHostPort(m.host, m.port)

	if err := smtp.SendMail(addr, auth, m.from, []string{to}, []byte(msg.String())); err != nil {
		log.Printf("[mail] delivery to %s failed: %v", to, err)
		return err
	}
	return nil
}

// SendOTP delivers a login code.
func (m *Mailer) SendOTP(to, code string, validMinutes int) error {
	body := fmt.Sprintf(
		"Your Libra Law verification code is:\n\n    %s\n\n"+
			"It expires in %d minutes. If you did not request this code, ignore this email "+
			"and consider changing your password.\n",
		code, validMinutes,
	)
	return m.Send(to, "Your Libra Law verification code", body)
}

// SendPasswordResetOTP delivers a forgot-password reset code. Kept separate
// from SendOTP so the subject line and copy are specific to a password reset
// rather than a login code, even though both share the same OTP mechanism.
func (m *Mailer) SendPasswordResetOTP(to, code string, validMinutes int) error {
	body := fmt.Sprintf(
		"We received a request to reset your Libra password.\n\n"+
			"Your one-time password (OTP) is:\n\n    %s\n\n"+
			"This OTP expires in %d minutes and can only be used once. "+
			"If you did not request a password reset, you can safely ignore this email — "+
			"your password will not be changed.\n",
		code, validMinutes,
	)
	return m.Send(to, "Libra Password Reset OTP", body)
}
