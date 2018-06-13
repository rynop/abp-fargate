package serverhooks

import (
	"context"
	"net/http"

	"github.com/twitchtv/twirp"
)

type headerContextKey string

var (
	contextKeyAuthorization = headerContextKey("Authorization")
	contextKeyXFromCDN      = headerContextKey("X-From-CDN")
)

//AddHeadersToContext Addd HTTP headers to context
func AddHeadersToContext(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		ctx = context.WithValue(ctx, contextKeyAuthorization, r.Header.Get("Authorization"))
		ctx = context.WithValue(ctx, contextKeyXFromCDN, r.Header.Get("X-From-CDN"))
		r = r.WithContext(ctx)
		h.ServeHTTP(w, r)
	})
}

//NewServerHooks Checks authN, X-From-CDN
func NewServerHooks() *twirp.ServerHooks {
	hooks := &twirp.ServerHooks{}

	hooks.RequestReceived = func(ctx context.Context) (context.Context, error) {
		if !checkAuthN(ctx) {
			twerr := twirp.NewError(twirp.Unauthenticated, "Unauthenticated")
			return nil, twerr
		}

		if !checkFromCdn(ctx) {
			twerr := twirp.NewError(twirp.Unauthenticated, "Missing/invalid From CDN Header")
			return nil, twerr
		}

		return ctx, nil
	}

	return hooks
}
