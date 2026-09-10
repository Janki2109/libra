package main

import (
	"context"
	"errors"
	"libra/config"
	"libra/migrations"
	"libra/routes"
	"libra/services"
	"libra/utils"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
)

func main() {
	config.LoadConfig()

	// Fail fast on a misconfigured production deployment rather than starting
	// up and quietly issuing forgeable tokens.
	if err := config.Validate(); err != nil {
		log.Fatalf("❌ %v", err)
	}

	if config.IsProduction() {
		// The default (debug) mode prints every registered route and every
		// request line, including query strings, to stdout.
		gin.SetMode(gin.ReleaseMode)
	}

	config.ConnectDatabase()
	defer config.DB.Close()

	if strings.EqualFold(config.GetEnv("RUN_MIGRATIONS", "true"), "true") {
		if err := migrations.Run(config.DB); err != nil {
			log.Fatalf("❌ Migration failed: %v", err)
		}
	}

	utils.InitFCM()

	// Advances expired trials to 'expired', lapsed subscriptions to 'past_due'
	// and then 'expired', and warns firm admins three days before a trial ends.
	// Without it, status only ever changed when someone paid.
	sweeperCtx, stopSweeper := context.WithCancel(context.Background())
	defer stopSweeper()
	services.NewSubscriptionSweeper(config.DB, 7*24*time.Hour).Start(sweeperCtx)
	// A lawyer has 30 minutes past a confirmed slot's scheduled time to
	// start the session before it's automatically marked expired.
	services.NewConsultationSweeper(config.DB, 30*time.Minute).Start(sweeperCtx)

	r := routes.SetupRoutes()

	port := config.GetEnv("PORT", "8080")
	srv := &http.Server{
		Addr:    ":" + port,
		Handler: r,
		// r.Run() sets no timeouts at all, so a slow or stalled client holds a
		// connection — and a goroutine — open indefinitely.
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}

	go func() {
		log.Printf("🏛️  Libra Law Practice API listening on :%s", port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal("Failed to start server: ", err)
		}
	}()

	// Drain in-flight requests on SIGTERM instead of dropping them. A deploy or
	// container restart previously cut off whatever was in progress — including
	// a payment being recorded.
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down…")

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Forced shutdown: %v", err)
	}
	log.Println("Stopped")
}
