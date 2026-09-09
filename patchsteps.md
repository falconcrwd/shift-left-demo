
1. use aws-actions/configure-aws-credentials@v6.2.4 assuming OIDC is set up

2. Authenticate to ECR - use Github action aws-actions/amazon-ecr-login@v2

3. patch the application image

docker run --user 0:0 \
  -v ${HOME}/.docker/config.json:/root/.docker/config.json \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --rm "$ECR_REPO":"$SENSOR_TAG" \
  falconutil patch-image ecsfargate \
  --source-image-uri "$SRC_IMAGE_REPO":"$SRC_TAG" \
  --target-image-uri "$DST_IMAGE_REPO":"$DST_TAG" \
  --falcon-image-uri "$ECR_REPO":"$SENSOR_TAG" \
  --cid <your_cid_with_checksum> \
  --falconctl-opts "--tags='jwong08-ecs'" \
  -–image-pull-policy "Always"


Assume the following Github variables/secrets are already available:

SRC_IMAGE_REPO=861305338103.dkr.ecr.us-west-2.amazonaws.com/jwong08/nopatch-nginx
SRC_TAG=1.0
DST_IMAGE_REPO=861305338103.dkr.ecr.us-west-2.amazonaws.com/jwong08/patched-nginx
DST_TAG=1.0
ECR_REPO=861305338103.dkr.ecr.us-west-2.amazonaws.com/jwong08/falcon-container
SENSOR_TAG=8.10.0-8002




--falconctl-opts "--tags='production,web-server'"