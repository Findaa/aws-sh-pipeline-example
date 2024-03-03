#!/bin/bash

. $CODEBUILD_SRC_DIR/log.sh

main() {
  IMAGE_TAG=$IMAGE_TAG-$(cat tagId.txt)
  pushDockerImage
  updateKubernetesImage
  rm tagId.txt
}

pushDockerImage() {
  inf "CI" "Pushing the Docker image..."
  docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG
  if [ $? -eq 0 ]; then
    inf "CI" "Pushed $IMAGE_REPO_NAME:$IMAGE_TAG to ECR."
  else
    err "CI" "Failure pushing $IMAGE_REPO_NAME:$IMAGE_TAG to ECR. Exiting..."
    exit
  fi
}

updateKubernetesImage() {
  inf "CD" "Updating akademia-gornoslaska cluster deployment images..."
  kubectl apply -f $CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml
  if [ $? -eq 0 ]; then
    inf "CD" "Updated akademia-gornoslaska deployment. Checking if scaler is present..."
  else
    err "CD" "Failure updating akademia-gornoslaska deployment. Exiting..."
    exit
  fi
  kubectl autoscale deployment akademia-gornoslaska --cpu-percent=95 --min=1 --max=5 -n $NAMESPACE
  if [ $? -eq 0 ]; then
    inf "CD" "Autoscaler added"
  else
    err "CD" "Autoscaler already present."
  fi
}

main
