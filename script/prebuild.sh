#!/bin/bash

. $CODEBUILD_SRC_DIR/log.sh

export POSTGRES_NAME="data-AG-$NAMESPACE"
export CLUSTER_NAME="AG-cluster"

CLUSTER_VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --region $AWS_DEFAULT_REGION --output text)
FILTERS=Name=description,Values="fargate-efs-securitygroup"
CLUSTER_EFS_SG_ID=$(aws ec2 describe-security-groups --filters $FILTERS --query "SecurityGroups[*].GroupId" --region $AWS_DEFAULT_REGION --output text)
CLUSTER_EFS_FS_ID="fs-id"

main() {
  initBuild
  createImageTag
  installKubectl
  checkKubernetesConfig
  updateConfigNamespace
  configureFargate
  configureMongo
  configureOauth
  authenticateDockerRegistry
}

initBuild() {
  inf "CI" "Build started on `date` in $AWS_DEFAULT_REGION $CLUSTER_NAME"
  inf "CI" "Logging into ECR..."
  docker login -u AWS -p $(aws ecr get-login-password --region $AWS_DEFAULT_REGION) $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com

  inf "CI" "Copying build files to build directory..."
  cp -r $CODEBUILD_SRC_DIR_SourceArtifact/* .
  cp -r $CODEBUILD_SRC_DIR_SourceArtifact/.mvn .

  inf "CI" "Build files copied to build directory."
}

createImageTag() {
   echo $(date +%s) > "tagId.txt"
   IMAGE_TAG=$IMAGE_TAG-$(cat tagId.txt)
}

installKubectl() {
  kubectl version --short --client
  if [ $? -eq 0 ]; then
    inf "CI" "kubectl already present. Updating config..."
    updateLocalK8sConfig
  else
    inf "CI" "Installing kubectl"
    curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.9/2020-11-02/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
    echo 'Check kubectl version'
    kubectl version --short --client
    if [ $? -eq 0 ]; then
      inf "CI" "Installed kubectl..."
      updateLocalK8sConfig
    else
      inf "CI" "Failure installing kubectl. Exiting..."
      exit
    fi
  fi
}

updateConfigNamespace(){
  inf "CI" "Updating namespace in config files..."
  sed -i "s/NAMESPACE_SED/$NAMESPACE/g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  sed -i "s/NAMESPACE_SED/$NAMESPACE/g" "$CODEBUILD_SRC_DIR/cloud/namespace.yml"
  sed -i "s/NAMESPACE_SED/$NAMESPACE/g" "$CODEBUILD_SRC_DIR/cloud/mongo-secret.yml"
  sed -i "s/NAMESPACE_SED/$NAMESPACE/g" "$CODEBUILD_SRC_DIR/cloud/oauth-secret.yml"

  kubectl apply -f $CODEBUILD_SRC_DIR/cloud/namespace.yml
}

configureFargate() {
  inf "CI" "Configuring Fargate..."
  PRIVATE_SUBNETS=$(aws ec2 describe-subnets --filters "Name=mapPublicIpOnLaunch,Values=false" --query "Subnets[*].SubnetId" --output text | tr -s '[:space:]' ' ')
  POD_EXECUTION_ROLE_ARN=$(aws iam list-roles --query "Roles[?starts_with(RoleName, 'AG-cluster-FargatePodExecutionRole')].Arn" --output text)

  inf "CI" "Creating Fargate profile..."
  aws eks create-fargate-profile \
      --fargate-profile-name fp-$NAMESPACE \
      --cluster-name $CLUSTER_NAME \
      --pod-execution-role-arn $POD_EXECUTION_ROLE_ARN \
      --selectors namespace=$NAMESPACE \
      --subnets $PRIVATE_SUBNETS
}

configureMongo() {
  inf "CI" "Configuring external MongoDB..."
  BASE64_MONGO_PASSWORD=$(echo -n "$MONGO_PASSWORD" | base64)

  sed -i "s/MONGO_USER_SED/$MONGO_USER/g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  sed -i "s/MONGO_DB_SED/$MONGO_DB/g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  sed -i "s/MONGO_PORT_SED/$MONGO_PORT/g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  sed -i "s/MONGO_ADMIN_DB_SED/$MONGO_ADMIN_DB/g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  sed -i "s/MONGO_HOST_SED/$MONGO_HOST/g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  sed -i "s/MONGO_SECRET_SED/$BASE64_MONGO_PASSWORD/g" "$CODEBUILD_SRC_DIR/cloud/mongo-secret.yml"

  kubectl apply -f $CODEBUILD_SRC_DIR/cloud/mongo-secret.yml
}

configureOauth() {
  inf "CI" "Configuring oAuth variables"
  BASE64_OAUTH_CLIENT_ID=$(echo -n "$OAUTH_CLIENT_ID" | base64)
  BASE64_OAUTH_CLIENT_SECRET=$(echo -n "$OAUTH_CLIENT_SECRET" | base64)

  sed -i "s#JWT_ISSUER_URL_SED#$JWT_ISSUER_URL#g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  sed -i "s#AWS_SED#$AWS_ACCOUNT_ID#g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  sed -i "s#OAUTH_AUTH_URL_SED#$OAUTH_AUTH_URL#g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  sed -i "s#OAUTH_TOKEN_URL_SED#$OAUTH_TOKEN_URL#g" "$CODEBUILD_SRC_DIR/cloud/akademia-gornoslaska.yml"
  sed -i "s#CLIENT_ID_SED#$BASE64_OAUTH_CLIENT_ID#g" "$CODEBUILD_SRC_DIR/cloud/oauth-secret.yml"
  sed -i "s#CLIENT_SECRET_SED#$BASE64_OAUTH_CLIENT_SECRET#g" "$CODEBUILD_SRC_DIR/cloud/oauth-secret.yml"

  kubectl apply -f $CODEBUILD_SRC_DIR/cloud/oauth-secret.yml
}

checkKubernetesConfig() {
  kubectl get service/kubernetes --kubeconfig=$HOME/.kube/config &>/dev/null
  if [ $? -eq 0 ]; then
    inf "CI" "Kubernetes config is valid."
  else
    err "CI" "Kubernetes config is invalid. Exiting..."
    exit
  fi
}

authenticateDockerRegistry() {
  inf "CI" "Logging into AWS ECR..."
  docker login -u AWS -p $(aws ecr get-login-password --region $AWS_DEFAULT_REGION) $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
  if [ $? -eq 0 ]; then
    inf "CI" "Logged into AWS ECR."
  else
    err "CI" "Failure logging into AWS ECR. Exiting..."
    exit
  fi
}

updateLocalK8sConfig() {
  aws eks --region $AWS_DEFAULT_REGION update-kubeconfig --name $CLUSTER_NAME
  if [ $? -eq 0 ]; then
    inf "CI" "Updated Kubernetes config."
  else
    err "CI" "Failure updating Kubernetes config. Exiting..."
    exit
  fi
}

main
