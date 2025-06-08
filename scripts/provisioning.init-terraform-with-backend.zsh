#!/usr/bin/env -S zsh -eu
setopt extended_glob

readonly SCRIPT_NAME=$(basename $0)
readonly termColorClear='\033[0m'
readonly termColorInfo='\033[1;32m'
readonly termColorWarn='\033[1;33m'
readonly termColorErr='\033[1;31m'
echoInfo() {
    echo -e "${termColorInfo}$1${termColorClear}"
}
echoWarn() {
    echo -e "${termColorWarn}$1${termColorClear}"
}
echoErr() {
    echo -e "${termColorErr}$1${termColorClear}"
}

# see: http://zsh.sourceforge.net/Doc/Release/Zsh-Modules.html#index-funcstack
if [[ ${#funcstack[@]} -ne 0 ]]; then
  echoErr 'The script is being sourced.'
  echoErr "Please run it is as a subshell such as \"sh ${SCRIPT_NAME}\""
  return 1
fi

local backends_are_validated=()
readonly TFSTATE_BACKEND_TYPES=(s3 none)
showHelp() {
  echo "Usage: ${SCRIPT_NAME} [OPTIONS]"
  echo "Options:"
  echo "\t-h, --help\t\tShow this help message."
  # See https://zsh.sourceforge.io/Guide/zshguide05.html#l124
  echo "\t-b, --backend type\tSpecify the Terraform backend: ${(j., .)TFSTATE_BACKEND_TYPES}."
}

exitBecauseIlligalBackendSpecified() {
  echo ""
  echoErr "Error: The backend \"${TFSTATE_BACKEND_TYPE}\" is not acceptable!!"
  echo ""
  showHelp
  exit 3
}

exitBecauseOfInsufficientCredentials() {
  echo ""
  echoErr "Error: Credentials are insufficient to initialize the backend \"${TFSTATE_BACKEND_TYPE}\" you selected!! Make sure your \".env\" and \"docker-compose.yml\"."
  echo ""
  showHelp
  exit 4
}

disableUnnecessaryBackendConfigs() {
  # Suppress the 'zsh: no matches found:' message.
  # See
  #   - https://zsh.sourceforge.io/Doc/Release/Options.html#Expansion-and-Globbing
  #   - https://zsh.sourceforge.io/Doc/Release/Options.html#index-LOCALOPTIONS
  unsetopt local_options nomatch
  for unnecessary_tf in $(ls -1 backend.*.tf~*${TFSTATE_BACKEND_TYPE}* 2> /dev/null || true)
  do
    echoWarn "WARN: The backend config ${unnecessary_tf} will be renamed to disable."
    echoWarn "$(mv --verbose ${unnecessary_tf}{,.disabled.txt})"
  done
}

updateAndPrepareTerraform() {
  sudo mkdir -p ${TF_DATA_DIR}
  sudo chmod a+rwx ${TF_DATA_DIR}
  sudo mkdir -p ${TF_PLUGIN_CACHE_DIR}
  sudo chmod a+rwx ${TF_PLUGIN_CACHE_DIR}

  # Detect terraform version
  rm -f .terraform-version
  sudo tfenv install min-required
  sudo tfenv use min-required
  terraform version -json | jq -r '.terraform_version' | tee -a /tmp/.terraform-version
  mv /tmp/.terraform-version .
}

setupBackendS3() {
  disableUnnecessaryBackendConfigs

  local -r BUCKET_NAME_FOR_PROVISIONING="${PROJECT_UNIQUE_ID}-provisioning"
  # Create the S3 bucket to save tfstate.
  aws s3 mb s3://${BUCKET_NAME_FOR_PROVISIONING}
  aws s3api put-public-access-block\
   --bucket ${BUCKET_NAME_FOR_PROVISIONING}\
   --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true' 
  aws s3api get-public-access-block\
   --bucket ${BUCKET_NAME_FOR_PROVISIONING}
  aws s3api put-bucket-versioning\
   --bucket ${BUCKET_NAME_FOR_PROVISIONING}\
   --versioning-configuration Status=Enabled
  aws s3api get-bucket-versioning\
   --bucket ${BUCKET_NAME_FOR_PROVISIONING}

  # Init Terraform with S3 backend.
  updateAndPrepareTerraform
  terraform init -backend-config="bucket=${BUCKET_NAME_FOR_PROVISIONING}"
}

setupBackendNone() {
  echoWarn "The backend type \"${TFSTATE_BACKEND_TYPE}\" is the dummy backend type."
  echoWarn "You are able to remove \"${SCRIPT_NAME}\" if you don't want to use Terraform and any Cloud Platforms."
}

# Detect selected backend type.
local TFSTATE_BACKEND_TYPE=none
args=$(getopt -o hb: -l help,backend: -- "$@") || exit 1
eval "set -- $args"
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help) showHelp; shift; exit 1;;
    -b | --backend) TFSTATE_BACKEND_TYPE=$2; shift 2;;
    --) shift; break;;
  esac
done
echoInfo "The backend type \"${TFSTATE_BACKEND_TYPE}\" was specified."
# Validate the backend type.
# See https://zsh.sourceforge.io/Guide/zshguide05.html#l121
if [[ ${TFSTATE_BACKEND_TYPES[(i)${TFSTATE_BACKEND_TYPE}]} -gt ${#TFSTATE_BACKEND_TYPES} ]]; then
  exitBecauseIlligalBackendSpecified
fi

# Validate AWS credentials if env vars are defined.
if [[ -v AWS_ACCESS_KEY_ID ]] && [[ -v AWS_ACCOUNT_ID ]] && [[ -v AWS_SECRET_ACCESS_KEY ]]; then
  echo ""
  echoInfo "Validate your AWS account using Access Key Id \"${AWS_ACCESS_KEY_ID}\" and credentials you export..."

  # Try to log in to the AWS account.
  aws sts get-access-key-info\
   --access-key-id=${AWS_ACCESS_KEY_ID}

  # Set the flag.
  backends_are_validated+=(s3)
fi

case ${TFSTATE_BACKEND_TYPE} in
  s3)
    if [[ ! -v PROJECT_UNIQUE_ID ]]; then
      echoErr 'Please set the $PROJECT_UNIQUE_ID variable.'
      echoErr 'It was canceled.'
      exit 2
    fi
    if [[ ${backends_are_validated[(i)${TFSTATE_BACKEND_TYPE}]} -gt ${#backends_are_validated} ]]; then
      exitBecauseOfInsufficientCredentials
    fi
    # Fall-through.
    # See https://zsh.sourceforge.io/Doc/Release/Shell-Grammar.html#Complex-Commands
    # > If the list that is executed is terminated with ;| the shell continues to scan the patterns looking for the next match, executing the corresponding list, and applying the rule for the corresponding terminator ;;, ;& or ;|.
    ;|
  s3)
    setupBackendS3
    ;;
  none)
    setupBackendNone
    ;;
  *)
    exitBecauseIlligalBackendSpecified
    ;;
esac
