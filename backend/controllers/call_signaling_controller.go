package controllers

import (
	"encoding/json"
	"libra/config"
	"libra/utils"
	"log"
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

// Free, self-hosted WebRTC signaling relay for the existing Audio/Video
// consultation booking flow. This process only ever forwards opaque
// offer/answer/ICE-candidate messages between the two parties on a given
// consultation — it never touches media itself (that stays peer-to-peer via
// WebRTC, using only free public STUN, no TURN/paid relay). No new backend
// dependency beyond gorilla/websocket; no new database table.

var callUpgrader = websocket.Upgrader{
	// Flutter web/mobile clients hit this cross-origin during dev (different
	// port/host than the API), same as every other route CorsMiddleware
	// already allows — the WS handshake has its own check because
	// gorilla/websocket doesn't go through Gin's CORS middleware.
	CheckOrigin: func(r *http.Request) bool { return true },
}

type callRoom struct {
	mu    sync.Mutex
	conns map[string]*websocket.Conn // userID -> connection (max 2)
}

var (
	callRoomsMu sync.Mutex
	callRooms   = map[string]*callRoom{}
)

func getOrCreateCallRoom(consultationID string) *callRoom {
	callRoomsMu.Lock()
	defer callRoomsMu.Unlock()
	room, ok := callRooms[consultationID]
	if !ok {
		room = &callRoom{conns: map[string]*websocket.Conn{}}
		callRooms[consultationID] = room
	}
	return room
}

func dropEmptyCallRoom(consultationID string) {
	callRoomsMu.Lock()
	defer callRoomsMu.Unlock()
	if room, ok := callRooms[consultationID]; ok {
		room.mu.Lock()
		empty := len(room.conns) == 0
		room.mu.Unlock()
		if empty {
			delete(callRooms, consultationID)
		}
	}
}

// CallSignalingWS handles the WebRTC signaling channel for one consultation.
// Auth can't ride the normal Authorization-header middleware here — browser
// WebSocket clients cannot set custom headers on the handshake — so the JWT
// is passed as a query parameter and validated the same way the header-based
// middleware validates it everywhere else.
func CallSignalingWS(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid id"})
		return
	}

	token := c.Query("token")
	claims, err := utils.ValidateToken(token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false, "message": "Invalid or expired token"})
		return
	}
	userID := claims.UserID

	// Only the two people this consultation is actually between may join its
	// call — never any other lawyer or client, even in the same firm.
	var lawyerID, clientID, status, consultationType string
	err = config.DB.QueryRow(`
		SELECT lawyer_id::text, client_id::text, status, consultation_type
		FROM consultations WHERE id=$1::uuid
	`, id).Scan(&lawyerID, &clientID, &status, &consultationType)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"success": false, "message": "Consultation not found"})
		return
	}
	if userID != lawyerID && userID != clientID {
		c.JSON(http.StatusForbidden, gin.H{"success": false, "message": "Not a participant on this consultation"})
		return
	}
	if status != "confirmed" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Consultation is not confirmed"})
		return
	}
	if consultationCallType(consultationType) == "chat" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "This consultation is chat-only"})
		return
	}

	conn, err := callUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("[call-signaling] upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	room := getOrCreateCallRoom(id)

	room.mu.Lock()
	// A stale connection under the same user (e.g. a refreshed tab) is
	// replaced rather than left to leak.
	if old, exists := room.conns[userID]; exists {
		old.Close()
	}
	room.conns[userID] = conn
	peerID := lawyerID
	if userID == lawyerID {
		peerID = clientID
	}
	peerConn, peerPresent := room.conns[peerID]
	room.mu.Unlock()

	if peerPresent {
		_ = peerConn.WriteJSON(gin.H{"type": "peer-joined"})
		_ = conn.WriteJSON(gin.H{"type": "peer-joined"})
	}

	defer func() {
		room.mu.Lock()
		if room.conns[userID] == conn {
			delete(room.conns, userID)
		}
		remaining, stillPresent := room.conns[peerID]
		room.mu.Unlock()
		if stillPresent {
			_ = remaining.WriteJSON(gin.H{"type": "peer-left"})
		}
		dropEmptyCallRoom(id)
	}()

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			return
		}
		// Opaque relay: offer/answer/ice-candidate/hangup payloads are
		// forwarded byte-for-byte to whichever peer is currently connected.
		// This process never parses SDP/ICE content, just routes it.
		var probe struct {
			Type string `json:"type"`
		}
		if json.Unmarshal(raw, &probe) != nil {
			continue
		}

		room.mu.Lock()
		peer, ok := room.conns[peerID]
		room.mu.Unlock()
		if ok {
			_ = peer.WriteMessage(websocket.TextMessage, raw)
		}
	}
}
