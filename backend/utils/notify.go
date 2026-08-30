package utils

import (
	"libra/config"

	"github.com/google/uuid"
)

// Notify writes the existing in-app notification row and, if FCM is
// configured, also pushes it to the user's registered devices. This is the
// single mechanism every notification event (any role) should go through —
// user_id -> user's device tokens -> send — so lawyer/client/student/admin
// notifications all share one code path instead of one each.
func Notify(userID, firmID, title, message, notifType string) {
	NotifyWithRef(userID, firmID, title, message, notifType, "", "")
}

// NotifyWithRef is Notify plus the optional reference_id/reference_type
// columns the notifications table already supports.
func NotifyWithRef(userID, firmID, title, message, notifType, referenceID, referenceType string) {
	if userID == "" {
		return
	}
	id := uuid.New().String()
	config.DB.Exec(`
		INSERT INTO notifications (id, user_id, firm_id, title, message, type, reference_id, reference_type)
		VALUES ($1, $2::uuid, NULLIF($3,'')::uuid, $4, $5, $6, NULLIF($7,'')::uuid, NULLIF($8,''))
	`, id, userID, firmID, title, message, notifType, referenceID, referenceType)

	go SendPushToUser(userID, title, message, notifType, referenceID, referenceType)
}
