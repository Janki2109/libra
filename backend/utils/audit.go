package utils

import (
	"encoding/json"
	"libra/config"
	"strings"

	"github.com/gin-gonic/gin"
)

// AuditEntry describes one action to record in audit_logs. Before/After are
// marshalled to JSONB as-is — callers must only pass safe, non-secret fields
// (a status string, a role name, an amount), never passwords, tokens, JWTs,
// or full documents, per the "no secrets in audit logs" requirement.
type AuditEntry struct {
	Action      string      // e.g. "LAWYER_VERIFIED" — see the fixed action-type list in the Audit Logs UI
	Module      string      // e.g. "lawyers", "payouts", "refunds"
	TargetType  string      // e.g. "user", "settlement", "case"
	TargetID    string      // uuid of the affected row, or ""
	Description string      // one-line human summary shown in the table/detail view
	Before      interface{} // nil if not applicable
	After       interface{} // nil if not applicable
	Status      string      // "success" (default) or "failed"
}

// deviceTypeFromUA is a deliberately simple, dependency-free heuristic —
// this app only needs "Mobile" vs "Desktop" for the audit table, not full
// user-agent parsing.
func deviceTypeFromUA(ua string) string {
	lower := strings.ToLower(ua)
	if strings.Contains(lower, "mobi") || strings.Contains(lower, "android") || strings.Contains(lower, "iphone") {
		return "Mobile"
	}
	if ua == "" {
		return ""
	}
	return "Desktop"
}

func toJSONB(v interface{}) []byte {
	if v == nil {
		return nil
	}
	b, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	return b
}

// LogAudit records one audit event for an authenticated, HTTP-request-driven
// action. Actor, role, IP and user-agent are all derived from the server's
// own request context — never trusted from client-supplied fields — per the
// "server determines actor/IP/metadata" requirement. Failures to write the
// audit row are swallowed (logged nowhere further) rather than failing the
// caller's actual action; an audit-trail outage must never block the
// underlying business operation.
func LogAudit(c *gin.Context, e AuditEntry) {
	status := e.Status
	if status == "" {
		status = "success"
	}
	actorID := UserID(c)
	actorRole := Role(c)
	var userIDArg interface{}
	if actorID != "" {
		userIDArg = actorID
	}
	firmID := FirmID(c)
	var firmIDArg interface{}
	if firmID != "" {
		firmIDArg = firmID
	}
	var targetIDArg interface{}
	if e.TargetID != "" {
		targetIDArg = e.TargetID
	}

	config.DB.Exec(`
		INSERT INTO audit_logs
			(id, user_id, actor_role, firm_id, action, module, target_type, reference_id,
			 description, old_values, new_values, ip_address, user_agent, device_type, status)
		VALUES (gen_random_uuid(), $1::uuid, $2, $3::uuid, $4, $5, $6, $7::uuid,
			$8, $9, $10, $11, $12, $13, $14)
	`, userIDArg, actorRole, firmIDArg, e.Action, e.Module, e.TargetType, targetIDArg,
		e.Description, toJSONB(e.Before), toJSONB(e.After), c.ClientIP(), c.GetHeader("User-Agent"),
		deviceTypeFromUA(c.GetHeader("User-Agent")), status)
}

// LogSystemAudit records an event performed by a background job or
// scheduler rather than an HTTP request — no gin.Context exists in that
// path, so there is no actor, IP, or user-agent to attribute it to. actor
// role is always "system" and must never be displayed as a human user.
func LogSystemAudit(e AuditEntry) {
	status := e.Status
	if status == "" {
		status = "success"
	}
	var targetIDArg interface{}
	if e.TargetID != "" {
		targetIDArg = e.TargetID
	}
	config.DB.Exec(`
		INSERT INTO audit_logs
			(id, user_id, actor_role, action, module, target_type, reference_id,
			 description, old_values, new_values, status)
		VALUES (gen_random_uuid(), NULL, 'system', $1, $2, $3, $4::uuid,
			$5, $6, $7, $8)
	`, e.Action, e.Module, e.TargetType, targetIDArg,
		e.Description, toJSONB(e.Before), toJSONB(e.After), status)
}
