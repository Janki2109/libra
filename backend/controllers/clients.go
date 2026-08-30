package controllers

import (
	"libra/services"
	"sync"
)

// Outbound service clients, built on first use rather than at package
// initialisation.
//
// They used to be plain package-level vars:
//
//	var razorpay = services.NewRazorpay()
//
// Go runs package-level initialisers before main(), which means every one of
// them read its configuration before main() had called config.LoadConfig() to
// populate the environment from .env. Each client captured empty strings and
// then reported itself unconfigured forever: payments returned 503, the webhook
// rejected every delivery as "secret unset", court lookups fell back to the
// placeholder card, and outbound email silently no-oped — on a deployment where
// all of it was configured correctly.
//
// sync.OnceValue defers construction until the first call, which is always
// after config is loaded.
var (
	razorpayOnce = sync.OnceValue(services.NewRazorpay)
	ecourtsOnce  = sync.OnceValue(services.NewECourtsClient)
	mailerOnce   = sync.OnceValue(services.NewMailer)
)

// razorpayClient returns the payment gateway client.
func razorpayClient() *services.Razorpay { return razorpayOnce() }

// ecourtsClient returns the court-data client.
func ecourtsClient() *services.ECourtsClient { return ecourtsOnce() }

// mailerClient returns the transactional email sender.
func mailerClient() *services.Mailer { return mailerOnce() }
