#!/usr/bin/env bash

abort() {
    printf "\n  \033[31mError: $@\033[0m\n\n" && exit 1
}

log() {
    printf "  \033[36m%10s\033[0m : \e[2m%s\e[22m\033[0m\n" "$1" "$2"
}

chkreqs() {
    WGET_PARAMS=("--no-check-certificate" "-q" "-O-")
    command -v wget > /dev/null && GET="wget ${WGET_PARAMS[@]}"
    test -z "$GET" && abort "wget required"
    
    command -v aws > /dev/null
    test $? -ne 0 && abort "aws cli required"
    
    command -v jq > /dev/null
    test $? -ne 0 && abort "jq (https://stedolan.github.io/jq/) required"
}

chkreqs

while [[ -z "$nestedStacksS3Bucket" ]]; do
    read -p "S3 bucket name storing your nested-stacks: " nestedStacksS3Bucket
done

read -p "S3 nested-stacks bucket region [us-east-1]: " nestedStacksS3BucketRegion
nestedStacksS3BucketRegion=${nestedStacksS3BucketRegion:-us-east-1}

read -p "aws cli profile [default]: " awsCliProfile
awsCliProfile=${awsCliProfile:-default}

declare -a arr=("master")
awsCliParams="--region ${nestedStacksS3BucketRegion} --profile ${awsCliProfile}"

for branch in "${arr[@]}"; do
    url="https://github.com/rynop/abp-fargate/archive/${branch}.zip"
    wget -qO- "${url}" | bsdtar -xf-
    if [ $? -ne 0 ] ; then
        abort "Error downloading ${url}"
    fi
    
    mv abp-fargate-${branch}/* .
    rm -r abp-fargate-${branch}
done

log 'Download code' 'done'

declare -a stackPaths=("vpc/three-sub-nat-gateway.yaml" "security-groups/ecs-in-vpc.yaml" "ecs/cluster-in-vpc.yaml")

for stackPath in "${arr[@]}"; do
    S3VER=$(aws ${awsCliParams} s3api list-object-versions --bucket ${nestedStacksS3Bucket} --prefix nested-stacks/${stackPath} | jq -r '.Versions[] | select(.IsLatest == true) | .VersionId')
    test -z "${S3VER}" && abort "Unable to find nested stack version at s3://${nestedStacksS3Bucket}/nested-stacks/${stackPath} See https://github.com/rynop/aws-blueprint/tree/master/nested-stacks"
    sed -i "s|${stackPath}?versionid=YourS3VersionId|${stackPath}?versionid=$S3VER|" aws/cloudformation/vpc-ecs-cluster.yaml
done

log 'Set s3 versionIds in aws/cloudformation/vpc-ecs-cluster.yaml' 'done'

grep YourS3VersionId aws/cloudformation/cf-apig-single-lambda-resources.yaml
test $? -eq 0 && abort "Unable to set your nested-stack template S3 versions"

cat <<TheMsg
Now run the following:
aws ssm put-parameter --name '/test/$githubRepoName/$gitBranch/$lambdaName/lambdaTimeout' --type 'String' --value '$lambdaTimeout'
aws ssm put-parameter --name '/staging/$githubRepoName/$gitBranch/$lambdaName/lambdaTimeout' --type 'String' --value '$lambdaTimeout'
aws ssm put-parameter --name '/prod/$githubRepoName/$gitBranch/$lambdaName/lambdaTimeout' --type 'String' --value '$lambdaTimeout'
aws ssm put-parameter --name '/test/$githubRepoName/$gitBranch/$lambdaName/lambdaMemory' --type 'String' --value '$lambdaMemory'
aws ssm put-parameter --name '/staging/$githubRepoName/$gitBranch/$lambdaName/lambdaMemory' --type 'String' --value '$lambdaMemory'
aws ssm put-parameter --name '/prod/$githubRepoName/$gitBranch/$lambdaName/lambdaMemory' --type 'String' --value '$lambdaMemory'

Create resources CloudFormation stacks with the names:
test--$githubRepoName--$gitBranch--[eyecatcher]--r
prod--$githubRepoName--$gitBranch--[eyecatcher]--r
CI/CD CloudFormation stack name will be:
$githubRepoName--$gitBranch--[eyecatcher]--cicd
LambdaName Parameter: $lambdaName
S3BucketForLambdaPackageZips: $nestedStacksS3Bucket
See https://github.com/rynop/abp-single-lambda-api/tree/$favLang for language specific CI/CD parameters
TheMsg