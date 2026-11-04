-- invoices already had upi_id/bank_account_name/bank_account_number/
-- bank_ifsc/bank_name (migration 009) but never bank_branch, even though
-- firms (migration 008) and the Create Invoice screen's form both already
-- had a Branch Name field — it was silently dropped before this, since
-- CreateInvoice never selected or inserted it. Nullable add: existing rows
-- are untouched, CreateInvoice now validates and stores it as mandatory for
-- every new invoice going forward.
ALTER TABLE invoices
    ADD COLUMN IF NOT EXISTS bank_branch VARCHAR(100);
