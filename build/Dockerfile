FROM golang:1.10.3
ARG GITHUB_ORG=rynop
ARG REPO=abp-fargate
# CODE_PATH is overridden in codebuild/build-docker-image.yaml.  The . entry here allows local building
ARG CODE_PATH=.
ADD . /go/src/github.com/${GITHUB_ORG}/${REPO}
WORKDIR /go/src/github.com/${GITHUB_ORG}/${REPO}/${CODE_PATH}

RUN wget https://github.com/Droplr/aws-env/raw/2005b61afcc4e3f36eb0cd9a684cf1ecefe156b9/bin/aws-env-linux-amd64 -O /bin/aws-env && chmod +x /bin/aws-env
RUN go build -o main . 

# using https://github.com/Droplr/aws-env, AWS_ENV_PATH is set in aws/cloudformation/fargate-[no|with]-elb.yaml
CMD ["/bin/bash", "-c", "eval $(aws-env) && ./main"]