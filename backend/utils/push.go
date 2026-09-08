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
	// Two ways to supply the service-account credentials: a file path (works
	// with Render's Secret Files, or any host that mounts one) or the raw
	// JSON pasted straight into a normal env var (simpler on hosts — Render's
	// free tier included — where uploading a secret file is an extra manual
	// step; the whole service-account JSON fits in one env var value).
	credPath := config.GetEnv("FIREBASE_CREDENTIALS_FILE", "")
	credJSON := config.GetEnv("FIREBASE_CREDENTIALS_JSON", "")
	if credPath == "" && credJSON == "" {
		log.Println("[fcm] FIREBASE_CREDENTIALS_FILE / FIREBASE_CREDENTIALS_JSON not set — " +
			"push notifications disabled (incoming-call alerts will not ring the other party), " +
			"in-app notifications still work")
		return
	}

	ctx := context.Background()

	var raw []byte
	if credJSON != "" {
		raw = []byte(credJSON)
	} else if b, readErr := os.ReadFile(credPath); readErr == nil {
		raw = b
	} else {
		log.Printf("[fcm] could not read FIREBASE_CREDENTIALS_FILE %q: %v", credPath, readErr)
		return
	}

	// The Admin SDK's Messaging() client needs a project ID up front and
	// doesn't reliably pull one from the credentials on its own — read it
	// directly from the same service-account JSON rather than requiring a
	// second, separate env var just to repeat a value already in it.
	var projectID string
	var cred struct {
		ProjectID string `json:"project_id"`
	}
	if json.Unmarshal(raw, &cred) == nil {
		projectID = cred.ProjectID
	}

	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID},
		option.WithCredentialsJSON(raw))
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
				"title":          title,
				"body":           body,
				"type":           notifType,
				"reference_id":   referenceID,
				"reference_type": referenceType,
			},
			// Without an explicit AndroidConfig, FCM defaults to NORMAL
			// priority, which Doze/App Standby can delay by minutes — no good
			// for an incoming-call alert. HIGH plus the channel this app
			// already creates (see FcmService in the Flutter app) makes sure
			// the system tray notification actually carries the sound +
			// vibration that channel was configured with.
			Android: &messaging.AndroidConfig{
				Priority: "high",
				Notification: &messaging.AndroidNotification{
					ChannelID: "default_channel",
				},
			},
			// Without an explicit APNSConfig, the Admin SDK does not set
			// aps.sound, so iOS delivers the notification silently even
			// though the app requested sound permission — this is what
			// actually supplies it.
			APNS: &messaging.APNSConfig{
				Payload: &messaging.APNSPayload{
					Aps: &messaging.Aps{
						Sound: "default",
					},
				},
				Headers: map[string]string{
					"apns-priority": "10",
				},
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
