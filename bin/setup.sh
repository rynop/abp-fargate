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

declare -a stackPaths=("vpc/three-sub-nat-gateway.yaml" "security-groups/ecs-in-vpc.yaml" "ecs/cluster-in-vpc.yaml" "rds/aurora.yaml")

for stackPath in "${stackPaths[@]}"; do
    S3VER=$(aws ${awsCliParams} s3api list-object-versions --bucket ${nestedStacksS3Bucket} --prefix nested-stacks/${stackPath} --query 'Versions[?IsLatest].[VersionId]' --output text)
    test -z "${S3VER}" && abort "Unable to find nested stack version at s3://${nestedStacksS3Bucket}/nested-stacks/${stackPath} See https://github.com/rynop/aws-blueprint/tree/master/nested-stacks"
    sed -i "s|${stackPath}?versionid=YourS3VersionId|${stackPath}?versionid=$S3VER|" aws/cloudformation/vpc-ecs-cluster.yaml
    sed -i "s|${stackPath}?versionid=YourS3VersionId|${stackPath}?versionid=$S3VER|" aws/cloudformation/app-resources.yaml
done

log 'Set s3 versionIds in aws/cloudformation/vpc-ecs-cluster.yaml' 'done'

grep YourS3VersionId aws/cloudformation/vpc-ecs-cluster.yaml
test $? -eq 0 && abort "Unable to set your nested-stack template S3 versions"

cat <<TheMsg

Values for attrs in aws/cloudformation/parameters/*--ecs-codepipeline-parameters.json:

S3BucketForLambdaPackageZips: $nestedStacksS3Bucket

TheMsg