#
# Create an OpenShift build box
#
NAME=$1
BASEOS=${2:-fedora19}

SERVER_GIT_URL=https://github.com/markllama/origin-server.git
SERVER_ROOT=$(basename $SERVER_GIT_URL .git)

thor origin:baseinstance ${NAME} --baseos $BASEOS ${VERBOSE}

HOSTNAME=$(thor ec2:instance hostname --name ${NAME} ${VERBOSE})

thor origin:prepare $HOSTNAME --baseos ${BASEOS} --packages git yum-utils tito ${VERBOSE}

thor remote:git:clone $HOSTNAME $SERVER_GIT_URL --baseos ${BASEOS} ${VERBOSE}

thor origin:depsrepo $HOSTNAME --baseos ${BASEOS} ${VERBOSE}

thor origin:builddep $HOSTNAME  $SERVER_ROOT --baseos ${BASEOS} ${VERBOSE}

thor origin:buildrpms $HOSTNAME $SERVER_ROOT --baseos ${BASEOS} ${VERBOSE}

