dir('build') { // switch to subdir
	stage( 'Configure Build' ) {
		sh 'cmake -DBUILD_TESTING:BOOL=ON -DSILENT_EXTERNALS=OFF ..'
	}
	if ( env.BRANCH_NAME == "master" ) {
		try {
			stage( 'Run tests' ) {
				sh 'ctest -j$(nproc) -D ContinuousStart'
				sh 'ctest -j$(nproc) -D ContinuousBuild -V'
				sh 'ctest -j$(nproc) -D ContinuousTest'
				sh 'ctest -j$(nproc) -D ContinuousCoverage'
				sh 'ctest -j$(nproc) -D ContinuousMemCheck'
				sh 'ctest -j$(nproc) -D ContinuousSubmit'
			}
		} catch (error) {
			currentBuild.result = 'FAILURE'
		}
	} else {

		try {
			stage( 'Run tests' ) {
				sh 'ctest -j$(nproc) -D ExperimentalStart'
				sh 'make -j$(nproc)'
				sh 'ctest -j$(nproc) -D ExperimentalTest'
				sh 'ctest -j$(nproc) -D ExperimentalCoverage'
				sh 'ctest -j$(nproc) -D ExperimentalMemCheck'
			}
		} catch (error) {
			currentBuild.result = 'FAILURE'
		}
		stage( 'Archive test results' ) {
			junit allowEmptyResults: true, testResults: '**/TEST-*.xml'
		}
	}
}
