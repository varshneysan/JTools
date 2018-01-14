def notifyStarted() {
    emailext (
        mimeType: 'text/html',
              subject: "STARTED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
              body: """<p>STARTED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]':</p>
                 <p>Check console output at &QUOT;<a href='${env.BUILD_URL}'>${env.JOB_NAME} [${env.BUILD_NUMBER}]</a>&QUOT;</p>""",
              to: "${PULL_REQUEST_USER_EMAIL_ADDRESS}"
    )
}

def notifySuccessful() {
    emailext (
        mimeType: 'text/html',
              subject: "SUCCESSFUL: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
              body: """<p>SUCCESSFUL: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]':</p>
                 <p>Check console output at &QUOT;<a href='${env.BUILD_URL}'>${env.JOB_NAME} [${env.BUILD_NUMBER}]</a>&QUOT;</p>""",
              to: "${PULL_REQUEST_USER_EMAIL_ADDRESS}"
    )
}

def notifyFailed() {
    emailext (
        mimeType: 'text/html',
              subject: "FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
              body: """<p>FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]':</p>
                 <p>Check console output at &QUOT;<a href='${env.BUILD_URL}'>${env.JOB_NAME} [${env.BUILD_NUMBER}]</a>&QUOT;</p>""",
              to: "${PULL_REQUEST_USER_EMAIL_ADDRESS}"
    )
}

def isPR() {
    return env.PULL_REQUEST_FROM_BRANCH != null
}

int run_ext_prog(String command) {
    def retstat = sh(script: command, returnStatus: true)
    return retstat
}


def merge_if_allowed() {
    def is_super_user = params.PULL_REQUEST_USER_EMAIL_ADDRESS == 'SWM-RnD-ESW-builduser@infinera.com'
    if (is_super_user) {
        echo "Attempting to merge"
        def merge_command = """"""
        merge_command += """${env.ESWTOOLS}/bin/merge_pr.py """
        merge_command += """-p GIB """
        merge_command += """-r cumulus """
        merge_command += """--change_id ${params.PULL_REQUEST_ID} -f"""
        run_ext_prog(merge_command)
    }
}

node('GIBSON_BUILD') {
    env.GIT_COMMIT = ""
    currentBuild.result = 'SUCCESS'
    try {

        timestamps {
            stage("Starting Cumulus build") {
                if (isPR()) {
                    notifyStarted()
                    env.GIT_COMMIT = PULL_REQUEST_FROM_HASH
                    echo "PULL_REQUEST_FROM_HASH ${PULL_REQUEST_FROM_HASH}"
                    sh '/files/apps/tm3000_jenkins/jenkins-bin/sh/set_build_status.sh INPROGRESS'
                }
            }

            stage("Cloning Cumulus repository") {
                if (isPR()) {
                    echo "Found pull request branch: ${PULL_REQUEST_FROM_BRANCH}"
                    checkout changelog: false,
                             poll: false,
                             scm: [$class: 'GitSCM',
                                   branches: [[name: "${PULL_REQUEST_FROM_BRANCH}"]],
                                   doGenerateSubmoduleConfigurations: false,
                                   extensions: [],
                                   submoduleCfg: [],
                                   userRemoteConfigs: [[url: 'ssh://git@se-bitbucket.infinera.com:7999/bitbucket/gib/cumulus.git']]]
                } else {
                    echo "Checking out master"
                    checkout changelog: false,
                        poll: false,
                        scm: [$class: 'GitSCM',
                              branches: [[name: "master"]],
                              doGenerateSubmoduleConfigurations: false,
                              extensions: [],
                              submoduleCfg: [],
                              userRemoteConfigs: [[url: 'ssh://git@se-bitbucket.infinera.com:7999/bitbucket/gib/cumulus.git']]]
                    env.GIT_COMMIT = sh returnStdout: true, script: 'git rev-parse HEAD'
                    echo "env.GIT_COMMIT = ${env.GIT_COMMIT}"
                }
                echo "env.GIT_COMMIT = ${env.GIT_COMMIT}"
                sh '/files/apps/tm3000_jenkins/jenkins-bin/sh/set_build_status.sh INPROGRESS'
            }

            withEnv(['REPOPATH=' + WORKSPACE]) {
                def YOCTO_SDK_SHA = sh returnStdout: true, script: "grep 'YOCTO_SDK_VERSION_SHA' ${REPOPATH}/build-config/3pp_versions.cmake | sed 's/set(YOCTO_SDK_VERSION_SHA \\([0-9a-f]*\\))/\\1/g' | tr -d '\n'"
                def YOCTO_RUNTIME_SHA = YOCTO_SDK_SHA

                stage('Getting RUNTIME image from Artifactory') {
                    def server = Artifactory.server "se-artif-prd"
                    def downloadSpec = """{
    "files": [
	{
	    "pattern": "gibson/com/infinera/yocto-dev-runtime/${YOCTO_RUNTIME_SHA}.tar.gz",
	    "target": "docker/runtime-env/",
	    "flat": "true"
	}
    ]
}"""
                    server.download(downloadSpec)
                }

                stage('BUILD docker image stage') {
                    def gibbld = docker.build('gibson-build-' + YOCTO_SDK_SHA,
                                              '--build-arg YOCTO_SDK_SHA=' + YOCTO_SDK_SHA +
                                              ' --build-arg ARTIFACTORY=https://se-artif-prd.infinera.com' +
                                              ' docker/build-env')

                    stage('Checking coding style') {
                        sh './run_astyle.sh'
                        try {
                            sh 'git diff-index --quiet HEAD --'
                        } catch (Exception err) {
                            echo "FAILED - Please format your code with ./run_astyle.sh and push again."
                            currentBuild.result = 'FAILURE'
                            throw err
                        }
                    }

                    stage("Compiling Cumulus") {
                        gibbld.inside('-v cumulus-ccache:/usr/local/src/ccache_dir:rw -e USER=builduser -u root') {
                            sh """
                           . /opt/poky/2.2.1/environment-setup-core2-64-poky-linux
                           rm -rf build
                           mkdir build
                           cd build
                           cmake -DSILENT_EXTERNALS=OFF -DUSE_HTTPS_REMOTES=ON ..
                           make -j12
                           """
                        }
                    }
                }

                stage('RUNTIME docker image stage') {
                    def gibrun = docker.build('gibson-runtime-' + YOCTO_RUNTIME_SHA,
                                              '--build-arg YOCTO_RUNTIME_SHA=' + YOCTO_RUNTIME_SHA +
                                              ' docker/runtime-env')

                    stage("Running tests") {
                        if (env.BRANCH_NAME == "master") {
                            gibrun.inside("-v cumulus-ccache:/usr/local/src/ccache_dir:rw -e USER=builduser -u root") {
                                sh """
                                   cd build
                                   ctest -D ContinuousStart
                                   ctest -D ContinuousBuild -V
                                   ctest -D ContinuousTest
                                   ctest -D ContinuousCoverage
###---!!!                                   ctest -D ContinuousMemCheck
                                   ctest -D ContinuousSubmit
                                   """
                            }
                        } else {
                            gibrun.inside("-v cumulus-ccache:/usr/local/src/ccache_dir:rw -e USER=builduser -u root") {
                                sh """
                                       cd build
                                       ctest -D ExperimentalStart
                                       ctest -D ExperimentalTest
                                       ctest -D ExperimentalCoverage
###---!!!                                       ctest -D ExperimentalMemCheck
                                       """
                            }


                            stage('Archive test results') {
                                junit allowEmptyResults: true, testResults: '**/TEST-*.xml'
                            }
                        }
                    }
                }
            }
        }
    } catch (error) {
        currentBuild.result = 'FAILURE'
    }
    stage ('Report results') {
        if (currentBuild.result == 'SUCCESS') {
            sh "/files/apps/tm3000_jenkins/jenkins-bin/sh/set_build_status.sh SUCCESSFUL"
            if (isPR()) {
                notifySuccessful()
                merge_if_allowed()
            }
        } else {
            sh "/files/apps/tm3000_jenkins/jenkins-bin/sh/set_build_status.sh FAILED"
            if (isPR()) {
                notifyFailed()
            }
        }
    }
}

