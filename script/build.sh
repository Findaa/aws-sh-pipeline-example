#!/bin/bash

. $CODEBUILD_SRC_DIR/log.sh

main() {
  IMAGE_TAG=$IMAGE_TAG-$(cat tagId.txt)
  buildImage
}

buildImage() {
  inf "CI" "Build started on `date`"
  inf "CI" "Building the Docker image..."
  docker build --quiet -t $IMAGE_REPO_NAME:$IMAGE_TAG .
  if [ $? -eq 0 ]; then
    inf "CI" "$IMAGE_REPO_NAME:$IMAGE_TAG built successfully. Tagging..."
    docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG
    sed -i "s/IMAGE_TAG_SED/$IMAGE_TAG/g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  else
    err "CI" "Failure building $IMAGE_REPO_NAME:$IMAGE_TAG. Exiting..."
    exit
  fi
}

main
