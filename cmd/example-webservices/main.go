package main

import (
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/rynop/abp-fargate/pkg/blogserver"
	"github.com/rynop/abp-fargate/pkg/imageserver"
	"github.com/rynop/abp-fargate/pkg/serverhooks"
	"github.com/rynop/abp-fargate/rpc/publicservices"
)

func setupRoutes() http.Handler {
	mux := http.NewServeMux()

	svrHooks := serverhooks.NewServerHooks()

	blogServerHandler := publicservices.NewBlogServer(&blogserver.Server{}, svrHooks)
	wrappedBlogHandler := serverhooks.AddHeadersToContext(blogServerHandler)
	mux.Handle(publicservices.BlogPathPrefix, wrappedBlogHandler)

	imageHandler := publicservices.NewImageServer(&imageserver.Server{}, svrHooks)
	wrappedImageHandler := serverhooks.AddHeadersToContext(imageHandler)
	mux.Handle(publicservices.ImagePathPrefix, wrappedImageHandler)

	appStage, _ := os.LookupEnv("APP_STAGE")
	mux.HandleFunc("/healthcheck", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "pong. stage:"+appStage)
	})

	return mux
}

func main() {
	//Dump all env vars
	for _, pair := range os.Environ() {
		fmt.Println(pair)
	}

	mux := setupRoutes()

	listenPort, exists := os.LookupEnv("LISTEN_PORT")
	if !exists {
		listenPort = "8080"
	}

	appStage, _ := os.LookupEnv("APP_STAGE")
	log.Print("Listening on " + listenPort + " in stage " + appStage + " docker image: --CodeImage--")

	http.ListenAndServe(":"+listenPort, mux)
}
