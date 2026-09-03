package utils

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"strings"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
	"libra/config"
)

var fcmClient *messaging.Client

// InitFCM sets up the Firebase Admin SDK from server-side credentials. This is
// a service-account JSON — never the Flutter app's google-services.json,
// which carries no send authority. Push is optional: without credentials the
// app still runs and the in-app notifications table still works, exactly
// like the existing SMTP/Razorpay "configured or 503" pattern.
func InitFCM() {
	credPath := config.GetEnv("FIREBASE_CREDENTIALS_FILE", "")
	if credPath == "" {
		log.Println("[fcm] FIREBASE_CREDENTIALS_FILE is not set — push notifications disabled, " +
			"in-app notifications still work")
		return
	}

	ctx := context.Background()

	// The Admin SDK's Messaging() client needs a project ID up front and
	// doesn't reliably pull one from the credentials file on its own — read
	// it directly from the same service-account JSON rather than requiring
	// a second, separate env var just to repeat a value already in the file.
	var projectID string
	if raw, readErr := os.ReadFile(credPath); readErr == nil {
		var cred struct {
			ProjectID string `json:"project_id"`
		}
		if json.Unmarshal(raw, &cred) == nil {
			projectID = cred.ProjectID
		}
	}

	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID},
		option.WithCredentialsFile(credPath))
	if err != nil {
		log.Printf("[fcm] failed to initialize Firebase app: %v", err)
		return
	}
	client, err := app.Messaging(ctx)
	if err != nil {
		log.Printf("[fcm] failed to initialize Messaging client: %v", err)
		return
	}
	fcmClient = client
	log.Println("[fcm] Firebase Cloud Messaging ready")
}

// SendPushToUser looks up every device token registered for a user and sends
// each one a push. Tokens FCM reports as unregistered/invalid are deleted so
// they stop being tried on every future notification.
//
// notifType/referenceID/referenceType are carried in the data payload (never
// shown to the user) so the client app can tell a plain notification apart
// from an incoming-call event and route accordingly, without a second API
// round trip — the existing in-app notifications list still works exactly as
// before since these are additive fields.
func SendPushToUser(userID, title, body, notifType, referenceID, referenceType string) {
	if fcmClient == nil {
		return // not configured — the DB notification row is still written
	}
	rows, err := config.DB.Query(`SELECT token FROM device_tokens WHERE user_id = $1::uuid`, userID)
	if err != nil {
		log.Printf("[fcm] failed to load device tokens for user %s: %v", userID, err)
		return
	}
	var tokens []string
	for rows.Next() {
		var t string
		if rows.Scan(&t) == nil {
			tokens = append(tokens, t)
		}
	}
	rows.Close()
	if len(tokens) == 0 {
		return
	}

	ctx := context.Background()
	for _, token := range tokens {
		_, err := fcmClient.Send(ctx, &messaging.Message{
			Token: token,
			Notification: &messaging.Notification{
				Title: title,
				Body:  body,
			},
			Data: map[string]string{
				"title":           title,
				"body":            body,
				"type":            notifType,
				"reference_id":    referenceID,
				"reference_type":  referenceType,
			},
		})
		if err != nil {
			// registration-token-not-registered / invalid-argument means the
			// token is dead (app uninstalled, token rotated) — stop sending to
			// it rather than retrying forever on every future notification.
			msg := err.Error()
			if strings.Contains(msg, "registration-token-not-registered") ||
				strings.Contains(msg, "invalid-argument") ||
				strings.Contains(msg, "NotFound") {
				config.DB.Exec(`DELETE FROM device_tokens WHERE token = $1`, token)
			} else {
				log.Printf("[fcm] send failed for user %s: %v", userID, err)
			}
		}
	}
}
