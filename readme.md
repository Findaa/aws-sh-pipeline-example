# Intro

Codebuild requires Dockerfile and buildspec.yml to be in project root, which is not compliant with GitOps principles.

This repository allows to keep this separation by utilising CodePipeline ability to merge separate repositories into one build project.

In that scenario, CodePipeline is fed with both application repository, and this one responsible for Ci/Cd.

# Contents
Repository contains shell scripts, Dockerfile, and yaml configs. All related to deployment of one, java 17 and maven based application.

For most use cases, to initialise your application, globally replace "akademia-gornoslaska" with name of desired service. 

Additional tuning required no more than variable changes, for details like database port or ECR repository.

# Usage 
To use it, create AWS CodeBuild project. Project will look for buildspec.yml file and execute its logic. For this project,
it's not in any scope of concern a its running shell scripts. 

Codebuild project accepts (by default requires, if optional will be noted) env variables such as:

* NAMESPACE - Desired cluster namespace for application
* AWS_DEFAULT_REGION - Desired AWS region for the deployment
* AWS_ACCOUNT_ID - Organisational account Id. This is required for permission purposes.
* IMAGE_TAG (optional) - Baseline for image name. Otherwise will only generate timestamp based id.
* IMAGE_REPO_NAME - ECR repository name for built image.
* AWS_ACCESS_KEY_ID - Privilliged user access key ID to allow access to related aws services.
* AWS_SECRET_ACCESS_KEY - Privilliged user secret key ID to allow access to related aws services.
* MONGO_USER (optional) - MongoDb username
* MONGO_PASSWORD (optional) - Plaintext mongo pass
* MONGO_DB (optional) - Mongo database name
* MONGO_ADMIN_DB (optional) - Required by some mongo versions, admin database name.
* OAUTH_CLIENT_ID (optional) - Authorization server user id.
* OAUTH_CLIENT_SECRET (optional) - Authorization server user id related access key.
* JWT_ISSUER_URL (optional)  - Authorization server jwt issuer endpoint
* OAUTH_AUTH_URL (optional) - Authorization server authorization endpoint
* OAUTH_TOKEN_URL (optional) - Authorization server token redirect endpoint

If variables are provided, script will perform [buildspec.yml](buildspec.yml) commands in order. 

Mind that this repo should be provided as an addition to application repository. This may be configured in CodePipeline.

