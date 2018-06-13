package serverhooks

import (
	"context"
	"log"
	"os"
)

func checkAuthN(ctx context.Context) bool {
	authN, ok := ctx.Value(contextKeyAuthorization).(string)
	log.Printf("Authorization: %v, %t", authN, ok)
	return true
}

func checkFromCdn(ctx context.Context) bool {
	xFromCdn, _ := ctx.Value(contextKeyXFromCDN).(string)
	log.Printf("X-From-CDN from header: %v", xFromCdn)
	fromCdnEnv, ok := os.LookupEnv("X_FROM_CDN")
	log.Printf("X_FROM_CDN from env: %v, %t", fromCdnEnv, ok)

	return ok && xFromCdn == fromCdnEnv
}
