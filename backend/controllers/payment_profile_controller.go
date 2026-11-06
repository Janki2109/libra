package controllers

import (
	"net/http"
	"strings"

	"libra/config"
	"libra/utils"

	"github.com/gin-gonic/gin"
)

// Saved payment profiles let a lawyer fill in UPI/bank details once and
// reuse them across invoices instead of retyping the same information every
// time. A profile is purely a convenience template for the Create Invoice
// form: selecting one just pre-fills fields client-side, and every invoice
// still stores its own independent snapshot of whichever fields it actually
// used (see migrations 009/038), so editing or deleting a profile later can
// never retroactively change an invoice that already went out.
//
// Every handler resolves firm_id from the authenticated session via
// utils.RequireFirm — never from the request body/path — and writes are
// admin-only, matching UpdateFirmBankDetails's existing rule that only a
// firm admin can touch anything that decides where client payments land.

type paymentProfile struct {
	ID                string `json:"id"`
	Name              string `json:"name"`
	UPIID             string `json:"upi_id"`
	BankAccountName   string `json:"bank_account_name"`
	BankAccountNumber string `json:"bank_account_number"` // masked on list/get
	BankIFSC          string `json:"bank_ifsc"`
	BankName          string `json:"bank_name"`
	BankBranch        string `json:"bank_branch"`
	IsDefault         bool   `json:"is_default"`
	CreatedAt         string `json:"created_at"`
}

// ListPaymentProfiles returns every saved profile for the caller's firm,
// most recently created first, with account numbers masked — the full
// number is never needed just to pick which profile to use.
func ListPaymentProfiles(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	rows, err := config.DB.Query(`
		SELECT id, name, upi_id, bank_account_name, bank_account_number,
		       bank_ifsc, bank_name, bank_branch, is_default, created_at
		FROM payment_profiles
		WHERE firm_id = $1
		ORDER BY is_default DESC, created_at DESC
	`, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to load payment profiles", err.Error())
		return
	}
	defer rows.Close()

	profiles := []paymentProfile{}
	for rows.Next() {
		var p paymentProfile
		if err := rows.Scan(&p.ID, &p.Name, &p.UPIID, &p.BankAccountName,
			&p.BankAccountNumber, &p.BankIFSC, &p.BankName, &p.BankBranch,
			&p.IsDefault, &p.CreatedAt); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to load payment profiles", err.Error())
			return
		}
		p.BankAccountNumber = maskAccountNumber(p.BankAccountNumber)
		profiles = append(profiles, p)
	}
	utils.Success(c, http.StatusOK, "Payment profiles", profiles)
}

type paymentProfileRequest struct {
	Name              string `json:"name"`
	UPIID             string `json:"upi_id"`
	BankAccountName   string `json:"bank_account_name"`
	BankAccountNumber string `json:"bank_account_number"`
	BankIFSC          string `json:"bank_ifsc"`
	BankName          string `json:"bank_name"`
	BankBranch        string `json:"bank_branch"`
	IsDefault         bool   `json:"is_default"`
}

// CreatePaymentProfile saves a new named payment profile for the caller's
// firm. The same validatePaymentDetails rule CreateInvoice enforces applies
// here too: a profile must be a complete, usable payment method (UPI, or
// full bank details) — saving an unusable half-filled profile defeats the
// point of reusing it later.
func CreatePaymentProfile(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden,
			"Only a firm admin can manage payment profiles", "insufficient role")
		return
	}
	var req paymentProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if nonEmptyNameTrim(req.Name) == "" {
		utils.Error(c, http.StatusBadRequest, "Profile name is required", "")
		return
	}
	if msg := validatePaymentDetails(req.UPIID, req.BankAccountName,
		req.BankAccountNumber, req.BankIFSC, req.BankName, req.BankBranch); msg != "" {
		utils.Error(c, http.StatusBadRequest, msg, "invalid or missing payment details")
		return
	}

	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to save profile", err.Error())
		return
	}
	defer tx.Rollback()

	if req.IsDefault {
		if _, err := tx.Exec(`UPDATE payment_profiles SET is_default = false WHERE firm_id = $1`, firmID); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to save profile", err.Error())
			return
		}
	}
	var id string
	err = tx.QueryRow(`
		INSERT INTO payment_profiles
			(firm_id, name, upi_id, bank_account_name, bank_account_number,
			 bank_ifsc, bank_name, bank_branch, is_default)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
		RETURNING id
	`, firmID, req.Name, req.UPIID, req.BankAccountName, req.BankAccountNumber,
		req.BankIFSC, req.BankName, req.BankBranch, req.IsDefault).Scan(&id)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to save profile", err.Error())
		return
	}
	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to save profile", err.Error())
		return
	}
	utils.Success(c, http.StatusCreated, "Payment profile saved", gin.H{"id": id})
}

// UpdatePaymentProfile overwrites an existing profile's details. Ownership
// is checked by scoping the UPDATE to firm_id, not by trusting the :id path
// param alone — a profile id from another firm simply matches zero rows.
func UpdatePaymentProfile(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden,
			"Only a firm admin can manage payment profiles", "insufficient role")
		return
	}
	id := c.Param("id")
	var req paymentProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if nonEmptyNameTrim(req.Name) == "" {
		utils.Error(c, http.StatusBadRequest, "Profile name is required", "")
		return
	}
	if msg := validatePaymentDetails(req.UPIID, req.BankAccountName,
		req.BankAccountNumber, req.BankIFSC, req.BankName, req.BankBranch); msg != "" {
		utils.Error(c, http.StatusBadRequest, msg, "invalid or missing payment details")
		return
	}

	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update profile", err.Error())
		return
	}
	defer tx.Rollback()

	if req.IsDefault {
		if _, err := tx.Exec(`UPDATE payment_profiles SET is_default = false WHERE firm_id = $1`, firmID); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to update profile", err.Error())
			return
		}
	}
	res, err := tx.Exec(`
		UPDATE payment_profiles
		SET name=$1, upi_id=$2, bank_account_name=$3, bank_account_number=$4,
		    bank_ifsc=$5, bank_name=$6, bank_branch=$7, is_default=$8, updated_at=now()
		WHERE id=$9::uuid AND firm_id=$10::uuid
	`, req.Name, req.UPIID, req.BankAccountName, req.BankAccountNumber,
		req.BankIFSC, req.BankName, req.BankBranch, req.IsDefault, id, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update profile", err.Error())
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		utils.Error(c, http.StatusNotFound, "Payment profile not found", "")
		return
	}
	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update profile", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Payment profile updated", nil)
}

// SetDefaultPaymentProfile marks one profile as the firm's default (used to
// pre-select it first on future invoices) and clears the flag on any other.
func SetDefaultPaymentProfile(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden,
			"Only a firm admin can manage payment profiles", "insufficient role")
		return
	}
	id := c.Param("id")
	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to set default profile", err.Error())
		return
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`UPDATE payment_profiles SET is_default = false WHERE firm_id = $1`, firmID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to set default profile", err.Error())
		return
	}
	res, err := tx.Exec(`UPDATE payment_profiles SET is_default = true, updated_at = now()
		WHERE id=$1::uuid AND firm_id=$2::uuid`, id, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to set default profile", err.Error())
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		utils.Error(c, http.StatusNotFound, "Payment profile not found", "")
		return
	}
	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to set default profile", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Default payment profile updated", nil)
}

// DeletePaymentProfile removes a saved profile. This never touches any
// invoice: invoices keep their own independently-stored snapshot of the
// payment details they were created with (see the package doc comment
// above), so deleting a profile cannot change a bill that already went out.
func DeletePaymentProfile(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden,
			"Only a firm admin can manage payment profiles", "insufficient role")
		return
	}
	id := c.Param("id")
	res, err := config.DB.Exec(`DELETE FROM payment_profiles WHERE id=$1::uuid AND firm_id=$2::uuid`, id, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to delete profile", err.Error())
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		utils.Error(c, http.StatusNotFound, "Payment profile not found", "")
		return
	}
	utils.Success(c, http.StatusOK, "Payment profile deleted", nil)
}

// nonEmptyNameTrim is a tiny local helper distinct from the package's
// nonEmptyName (which requires >=2 chars) so a profile name's own rule —
// just "not blank" — isn't coupled to the bank-field length rule.
func nonEmptyNameTrim(s string) string {
	return strings.TrimSpace(s)
}
