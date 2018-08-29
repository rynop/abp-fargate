# abp-fargate

An [aws-blueprint](https://github.com/rynop/aws-blueprint) example for a ECS fargate based app, with or without an ELB

## Setup

1. Run the setup script from your local git repo dir: 
    ```
    wget -q https://raw.githubusercontent.com/rynop/abp-fargate/master/bin/setup.sh; bash setup.sh; rm setup.sh
    ```

    This:
    *  Copies this code in this repo to yours
    *  Sets `NestedStacksS3Bucket` and s3 versions of your `nested-stacks` in your [vpc-ecs-cluster](./aws/cloudformation/vpc-ecs-cluster.yaml) file.
1. Update the code to use your go package, by doing an extended find and replace of all occurances of `rynop/abp-fargate` with your golang package namespace.
1. Create an ECR [image repository](https://console.aws.amazon.com/ecs/home?region=us-east-1#/repositories).  Naming convention `<git repo name>/<branch>`.

    Populate it with an inital image. See [Dockerfile](./Dockerfile) for an example (make sure to set `GITHUB_ORG`,`REPO`).  From git repo root run:
    ```
    aws ecr get-login --no-include-email --region us-east-1
    docker build --build-arg CODE_PATH=cmd/example-webservices -t abp-fargate/master:initial .
    docker tag abp-fargate/master:initial 1111.dkr.ecr.us-east-1.amazonaws.com/abp-fargate/master:initial
    docker push 1111.dkr.ecr.us-east-1.amazonaws.com/abp-fargate/master:initial
    ```
1. Create a new CloudFormation stack using [./aws/cloudformation/vpc-ecs-cluster.yaml](./aws/cloudformation/vpc-ecs-cluster.yaml).  This creates an ECS Cluster inside its own VPC. This cluster will run your `test`,`staging`,`prod` stages (task per stage). CloudFormation stack naming convention: `<project>--ecs-cluster`. Ex: `imgManip--ecs-cluster`
1. Review **Code Specifics** [below](https://github.com/rynop/abp-fargate#code-specifics)
1. Define **Environment variables** [below](https://github.com/rynop/abp-fargate#enviornment-variables)
1. Create a Github user (acct will just be used to read repos for CI/CD), give it read auth to your github repo.  Create a personal access token for this user at https://github.com/settings/tokens.  This token will be used by the CI/CD to pull code.
1. Create a CloudFormation stack for your resources (dynamo,s3, etc).  You must also define an IAM role for your ECS tasks.  Use [./aws/cloudformation/app-resources.yaml](./aws/cloudformation/app-resources.yaml).  Create one of these for `test`, `staging` and `prod`.  Naming convention `[stage]--[repo]--[branch]--[eyecatcher]--r`.  Ex `test--abp-fargate--master--imgManip--r`
1. Set stage specific parameters in [./aws/cloudformation/parameters](./aws/cloudformation/parameters/).  These are passed by the CI/CD stack to create each stage's CloudFormation stack.
1. Use [cloudformation-test-staging-prod.yaml](https://github.com/rynop/aws-blueprint/blob/master/pipelines/cicd/cloudformation-test-staging-prod.yaml) to create a codepipeline CI/CD that builds a docker image and updates ECS cluster with stage promotion approval. CloudFormation stack naming convention: `[repo]--[branch]--[service]--cicd`.  The pipeline will create a CloudFormation stack for each stage (`test`,`staging`,`prod`).
    1. Param `RelCloudFormationTemplatePath`: if your app needs an ELB specify `aws/cloudformation/fargate-with-elb.yaml`. (located [here](./aws/cloudformation/fargate-with-elb.yaml) if you want to look) otherwise, specify `aws/cloudformation/fargate-no-elb.yaml` (located [here](./aws/cloudformation/fargate-no-elb.yaml) if you want to look). 
    1. If using `fargate-with-elb.yaml` your app **MUST**:
        * [accept health checks](./cmd/example-webservices/main.go#L29) at `/healthcheck`
        * [Verify](./pkg/serverhooks/main.go#L38) the value of the `X-From-CDN` header matches the value you set in the `VerifyFromCfHeaderVal` parameter in [`<stage>--ecs-codepipeline-parameters.json`](./aws/cloudformation/parameters/)
        * Edit your cloudfront > dist settings > change Security policy to `TLSv1.1_2016`.  CloudFormation does not support this parameter yet.
        * Create a DNS entry in route53 for production that consumers will use.  The cloud formation creates one for `prod--` but you do not want to use this as the CloudFormation can be deleted.
1. Deploy your code, CodePipeline will run.  Once `test` stage is successfully executed test sample code via:
    ```
    curl -H 'Content-Type:application/json' -H 'Authorization: Bearer aaa' -H 'X-FROM-CDN: [your X_FROM_CDN env value]' -d '{"term":"wahooo"}' https://[CloudFormation Output CNAME from test--[repo]--[branch]-[service]--fargagte]/com.rynop.twirpl.publicservices.Image/CreateGiphy
    ```        

### Enviornment variables

We use [Systems manager parameter store](https://console.aws.amazon.com/systems-manager/parameters) to define environment variables, using the namespace convention `/<stage>/<repoName>/<branch>/ecsEnvs/<env var name>`. The `SsmEnvPrefix` parameter in `aws/cloudformation/parameters/*.json` defines this path.  [aws-env](https://github.com/Droplr/aws-env) is used to load the env vars from SSM into your container.  

`APP_STAGE` and `LISTEN_PORT` will automatically be set inside your container when running in ECS.

`X_FROM_CDN` is required if using an ELB - remember to do this for `staging` and `prod` stages too.

```
aws ssm put-parameter --name '/test/abp-fargate/master/ecsEnvs/X_FROM_CDN' --type 'String' --value 'fromCDN'
```

You can use [this helper script](https://github.com/rynop/aws-blueprint/blob/master/bin/fargate-ssm-env-var-helper.sh) to generate a bash script that will run the `aws ssm` commands for you.

### Code specifics

This example is using golang and the [Twirp RPC framework](https://github.com/twitchtv/twirp).  Project layout is based on [golang-standards/project-layout](https://github.com/golang-standards/project-layout)

We recommend using [retool](https://github.com/twitchtv/retool) to manage your tools (like [dep](https://github.com/golang/dep)).  Why?  If you work with anyone else on your project, and they have different versions of their tools, everything turns to shit.

1. Update [./Dockerfile](./Dockerfile) to set your github org and repo.
1. Update [./aws/codebuild/go-lint-test.yaml](./aws/codebuild/go-lint-test.yaml) to set your github org and repo (`GO_PKG`).
1. [Install retool](https://github.com/twitchtv/retool#usage): `go get github.com/twitchtv/retool`. Make sure to add `$GOPATH/bin` to your PATH
1. Run:
    ```
    retool add github.com/golang/dep/cmd/dep origin/master
    retool add github.com/golang/lint/golint origin/master
    retool add github.com/golang/protobuf/protoc-gen-go origin/master
    retool add github.com/twitchtv/twirp/protoc-gen-twirp origin/v6_prerelease
    retool do dep init  #If this was existing code you'd run `retool do dep ensure`
    ```
1. Add dependency example: 
    ```
    retool do dep ensure -add github.com/apex/gateway github.com/aws/aws-lambda-go
    ```
1. Auto-generate the code:
    ```
    retool do protoc --proto_path=$GOPATH/src:. --twirp_out=. --go_out=. ./rpc/publicservices/service.proto 
    retool do protoc --proto_path=$GOPATH/src:. --twirp_out=. --go_out=. ./rpc/adminservices/service.proto 
    ```    
1. For this example, the interface implementations have been hand created in `pkg/`. Take a look.
1. Example to consume twirp API in this example: 
    ```
    curl -H 'Content-Type:application/json' -H 'Authorization: Bearer aaa' -H 'X-FROM-CDN: <your VerifyFromCfHeaderVal>' -d '{"term":"wahooo"}' https://<--r output CNAME>/com.rynop.twirpl.publicservices.Image/CreateGiphy
    ```

## Testing locally:
1.  Set `LOCAL_LISTEN_PORT` and `X_FROM_CDN` env vars. (Fish: `set -gx LOCAL_LISTEN_PORT 8080`, `set -gx X_FROM_CDN localTest`)
1.  Build & run: `cd cmd/example-webservices`, `go build -o /tmp/main .; /tmp/main`
1.  Hit endpoint: `curl -v -H 'Content-Type:application/json' -H 'Authorization: Bearer aaa' -H 'X-FROM-CDN: localTest' -d '{"term":"wahooo"}' http://localhost:8080/com.rynop.twirpl.publicservices.Image/CreateGiphy`


## Building docker image locally

```
docker build --build-arg CODE_PATH=cmd/example-webservices -t abp-fargate/master:initial .
```
