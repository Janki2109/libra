package controllers

import (
	"encoding/json"
	"libra/config"
	"libra/utils"
	"log"
	"net/http"
	"sync"
	"time"

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

// writeJSON/writeMessage serialize every write to a connection in this room
// behind the same mutex that guards room.conns. gorilla/websocket requires
// at most one concurrent writer per connection; without this, the relay loop
// (writing to a peer's conn) and that peer's own goroutine (writing a ping,
// or its own peer-joined/peer-left notice) could call WriteMessage on the
// same underlying conn from two goroutines at once, corrupting the frame.
func (r *callRoom) writeJSON(conn *websocket.Conn, v interface{}) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	return conn.WriteJSON(v)
}

func (r *callRoom) writeMessage(conn *websocket.Conn, messageType int, data []byte) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	return conn.WriteMessage(messageType, data)
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
	// Every rejection below used to respond with a raw c.JSON(...) instead of
	// utils.Error(...) — the only place in this codebase that does that —
	// which meant none of them were ever logged. A call that failed here for
	// any reason (expired token, wrong status, not a participant) looked
	// completely silent in the logs: the whole reason "why is this call not
	// connecting" was undiagnosable from the server side. Every exit path
	// now logs, so the next failed call attempt actually shows up.
	if !isUUID(id) {
		log.Printf("[call-signaling] rejected: invalid consultation id %q", id)
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Invalid id"})
		return
	}

	token := c.Query("token")
	claims, err := utils.ValidateToken(token)
	if err != nil {
		log.Printf("[call-signaling] rejected for consultation %s: invalid/expired token: %v", id, err)
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
		log.Printf("[call-signaling] rejected: consultation %s not found: %v", id, err)
		c.JSON(http.StatusNotFound, gin.H{"success": false, "message": "Consultation not found"})
		return
	}
	if userID != lawyerID && userID != clientID {
		log.Printf("[call-signaling] rejected: user %s is not a participant on consultation %s", userID, id)
		c.JSON(http.StatusForbidden, gin.H{"success": false, "message": "Not a participant on this consultation"})
		return
	}
	if status != "confirmed" {
		log.Printf("[call-signaling] rejected: consultation %s has status=%q, not confirmed (user %s)", id, status, userID)
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "Consultation is not confirmed"})
		return
	}
	if consultationCallType(consultationType) == "chat" {
		log.Printf("[call-signaling] rejected: consultation %s is chat-only (user %s)", id, userID)
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "message": "This consultation is chat-only"})
		return
	}

	conn, err := callUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("[call-signaling] upgrade failed for consultation %s, user %s: %v", id, userID, err)
		return
	}
	defer conn.Close()
	log.Printf("[call-signaling] user %s connected to consultation %s", userID, id)

	room := getOrCreateCallRoom(id)

	// http.Server{ReadTimeout, WriteTimeout} (main.go) apply to the raw
	// connection before Upgrade's Hijack() ever runs, and Hijack does not
	// clear them — so without this, ReadMessage/WriteMessage below start
	// failing with an i/o timeout once those windows pass, silently ending
	// any call that runs long. A call's WS traffic is bursty (an offer/
	// answer/ICE exchange at setup, then near-silence for the rest of the
	// call, since media itself flows peer-to-peer, not through this socket),
	// so a ping/pong keepalive is what actually keeps the connection (and
	// any idle-timeout in front of it, e.g. a PaaS's own reverse proxy)
	// alive for the call's whole duration, not just deadlines.
	conn.SetReadDeadline(time.Time{})
	_ = conn.SetWriteDeadline(time.Time{})
	const pongWait = 60 * time.Second
	conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})
	pingTicker := time.NewTicker(30 * time.Second)
	defer pingTicker.Stop()
	go func() {
		for range pingTicker.C {
			if err := room.writeMessage(conn, websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}()

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
		log.Printf("[call-signaling] peer-joined fired for consultation %s (user %s found peer %s already connected)", id, userID, peerID)
		_ = room.writeJSON(peerConn, gin.H{"type": "peer-joined"})
		_ = room.writeJSON(conn, gin.H{"type": "peer-joined"})
	} else {
		log.Printf("[call-signaling] user %s is first to join consultation %s, waiting for peer %s", userID, id, peerID)
	}

	defer func() {
		room.mu.Lock()
		if room.conns[userID] == conn {
			delete(room.conns, userID)
		}
		remaining, stillPresent := room.conns[peerID]
		room.mu.Unlock()
		if stillPresent {
			_ = room.writeJSON(remaining, gin.H{"type": "peer-left"})
		}
		dropEmptyCallRoom(id)
		log.Printf("[call-signaling] user %s disconnected from consultation %s", userID, id)
	}()

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			log.Printf("[call-signaling] read ended for user %s on consultation %s: %v", userID, id, err)
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
		// Logs the message type only (offer/answer/ice-candidate/hangup) and
		// whether a live peer connection was found to relay it to — never the
		// SDP/ICE payload itself. "ok=false" here, specifically, is what
		// "rings but never connects" looks like from the server's side: the
		// caller's offer has nowhere to go because the callee's socket was
		// never in room.conns when this arrived.
		log.Printf("[call-signaling] consultation %s: %s from %s -> peer %s (peer connected: %v)",
			id, probe.Type, userID, peerID, ok)
		if ok {
			_ = room.writeMessage(peer, websocket.TextMessage, raw)
		}
	}
}
