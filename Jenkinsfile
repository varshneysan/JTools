env.Host="${JOB_NAME}"
env.P4CLIENT="CLV_${Branch}_${Host}"
env.CCMAIL="svarshney@infinera.com,mkrishan@infinera.com,DUpadhaye@infinera.com,jili@infinera.com,mkrishna@infinera.com"
CL=ChangeList.split(",")
env.mcl=CL[0]

env.debug=""
// Keep debug="" or debug="true to switch it on"

node ("${Host}"){
    withEnv(["WORKSPACE=${pwd()}"]) {
    env.LOGSERR="${WORKSPACE}/LOGS_ERR"
	if (env.Host ==~ /IN-.*/ || env.Host ==~ /in-.*/) {
        env.WPath="/home/bangbuild/CLVERI/workspace"
		env.LOGS="/home/bangbuild/CLVERI/LOGS/${BUILD_NUMBER}/"
		env.P4PORT='indperforce:1666'
		env.P4PASSWD="BD09EFDFEEA034D237ADE61B256006A9"
	}
	if (env.Host ==~ /sv-.*/) {
	    env.WPath="/bld_home/bangbuild/CLVERI/workspace"
		env.LOGS="/bld_home/bangbuild/CLVERI/LOGS/${BUILD_NUMBER}/"
		env.P4PORT='perforce:1666'
		env.P4PASSWD="BD09EFDFEEA034D237ADE61B256006A9"
		
	}
	if (env.debug) {
		env.CCMAIL="svarshney@infinera.com"
		env.mailer="svarshney@infinera.com"
	}
	if (env.IsDev == 'Yes') {
		env.DepotPath="//swdepot/dev/${Branch}"
	} else {
		env.DepotPath="//swdepot/${Branch}"
	}
	try {
    stage ('Preparation')
    {
	build job: 'Pre-iSubmit BM Update', parameters: [string(name: 'Changelist', value: '${Changelist}'), string(name: 'Host', value: '${Host}'), string(name: 'Build_Number', value: '${BUILD_NUMBER}')], wait: false
        checkout([$class: 'GitSCM', branches: [[name: '*/master']], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'CloneOption', noTags: true, reference: '', shallow: true]], submoduleCfg: [], userRemoteConfigs: [[credentialsId: '735466fc-bc83-4554-b2f8-00721c6c1928', url: 'git@sv-gitswarm-prd.infinera.com:svarshney/Tools.git']]])
        sh 'sh get_p4_ws.sh ${Branch}'
        sh 'if [ -d ${LOGSERR} ]; then rm -rf ${LOGSERR}; fi'
        sh 'if [ ! -d ${LOGS} ]; then mkdir -p ${LOGS};fi;'
        sh 'p4 -u bangbuild -P ${P4PASSWD} -c ${P4CLIENT} sync $DepotPath/etc2.0/... > ${LOGS}/IQNOS_Sync.log 2>&1'
		echo "INFO : P4CLIENT -  ${P4CLIENT}"
		echo "INFO : LOGS - ${LOGS}"
		echo "INFO : LOGSERR - ${LOGSERR}"
    }
    
    stage ('Synching WA') 
    {
		parallel (
		"IQNOS" : {
		sh 'echo "Synching Branch" && p4 -u bangbuild -P ${P4PASSWD} -c ${P4CLIENT} sync $DepotPath/... >> ${LOGS}/IQNOS_Sync.log 2>&1'
		},
		"2dParty": {
		sh 'echo "Synching 2dParty"; \
		    cd ${WPath}/${Branch}/etc2.0 && alias p4="p4 -u bangbuild -P ${P4PASSWD}" && ./BuildManage.sh -s > ${LOGS}/2dParty.log 2>&1'
		sh 'if [ "${Branch}" ==  "main" ]; then p4 -u bangbuild -P ${P4PASSWD} -c ${P4CLIENT}  sync //swdepot/3dParty/NM/... > ${LOGS}/3dParty.log 2>&1 ;fi'
        }
		)
    }
    } catch (Exception e) {
        sh 'p4 -u bangbuild -P ${P4PASSWD} -c $P4CLIENT revert //...'
        sh 'p4 -u bangbuild -P ${P4PASSWD} client -d $P4CLIENT'
        build job: 'UpdateCL', parameters: [string(name: 'CLs', value: "${ChangeList}"), string(name: 'State', value: 'READY')], wait: false
        build job: 'UpdateBoxState', parameters: [string(name: 'BuildBox', value: "${Host}"), string(name: 'InUsed', value: 'NO')], wait: false
        mail (to: 'svarshney@infinera.com,mkrishan@infinera.com',    
           subject: 'pre-iSubmit - Initial stage issue. Please take a look.',
           body: "Hi, Looks like Initial Stage issue for OSubmit job for URL : ${env.BUILD_URL}. This need your attention immediately. Logs are available at ${LOGS}" )
		currentBuild.description = "CLs : ${ChangeList}"
		sh 'exit 1'
    }
    
	try {
		stage('UnShelving') {
			echo "All CL to unshelve"
			sh 'CLs=`echo "${ChangeList}" | tr "," " "`; for cl in $CLs; do p4 -u bangbuild -P ${P4PASSWD} unshelve -s $cl; done'
			sh 'p4 -u bangbuild -P ${P4PASSWD} update $DepotPath/... '
			sh 'for f in `${WORKSPACE}/get_component_path.sh ${ChangeList}`; do if [ ${f} ]; then p4 -u bangbuild -P ${P4PASSWD} update ${f}...; fi;done'
			sh 'p4 -u bangbuild -P ${P4PASSWD} resolve -am'
			sh 'p4 -u bangbuild -P ${P4PASSWD} opened'
			sh 'clist=`p4 -u bangbuild -P ${P4PASSWD} resolve -n | wc -l`; if [ $clist -gt 0 ]; then exit 1; fi'
			
		} 
	} catch (Exception e) {
	    mail (to: "${mailer}",    
			cc: "${CCMAIL}",
			subject: "pre-iSubmit : Change# ${ChangeList} is rejected due code conflict.",
			body: "Your Changelists ${ChangeList} got rejected due to code conflict. Pls refer ${env.BUILD_URL} for more info. You have to re-submit your change after resolving the conflicts" )
		currentBuild.description = "CLs : ${ChangeList}"
		sh 'p4 -u bangbuild -P ${P4PASSWD} -c $P4CLIENT revert //...'
		sh 'rm -rf ${WPath}/* ${LOGSERR};p4 -u bangbuild -P ${P4PASSWD} client -d $P4CLIENT'
		build job: 'Pre-iSubmit CL Rejection', parameters: [string(name: 'Changelist', value: "${ChangeList}"), string(name: 'Reason', value: 'CONFLICTING')], wait: false
		sh 'exit 1'
	}
	
	try { 
      stage('Compilation') {
        
        build job: 'UpdateCL', parameters: [string(name: 'CLs', value: "${ChangeList}"), string(name: 'State', value: 'INCOMPILATION')], wait: false
        sh 'sed -i s/.[^.*]*$/."$mcl"/g  "${WPath}/${Branch}/src_ne/latest.txt"'
        sh 'cd ${WPath}/${Branch}/etc2.0 && HOSTNAME=$Host ./BuildManage.sh -s -b ALL > ${LOGS}/BuildLog.txt 2>&1'
        sh 'lcount=`ls ${WPath}/${Branch}/src_ne/ | grep parallelbuild.*.log | wc -l` && errc=`ls ${WPath}/${Branch}/src_ne/ | grep "parallelbuild.*.err" | wc -l` && if [[ -d "${WPath}/${Branch}/tar_ne" &&  $errc -eq 0 ]]; then  echo "Build Artifacts Generated" && exit 0; else mkdir ${LOGSERR} && cp ${WPath}/${Branch}/src_ne/parallelbuild.*.err ${LOGSERR}/; if [ $lcount -gt 0 ]; then cp ${WPath}/${Branch}/src_ne/parallelbuild.*.log ${LOGSERR}/; else cp ${LOGS}/BuildLog.txt ${LOGSERR}/BuildLog.log; fi; exit 1; fi'
      }   
    } catch (Exception e) {
        archiveArtifacts artifacts: 'LOGS_ERR/*'
		
		mail (to: "${mailer}",    
			cc: "${CCMAIL}",
			subject: "pre-iSubmit : Change# ${ChangeList} is rejected due to compile errors. Please take a look.",
			body: "Your Changelists ${ChangeList} got rejected due to compilation error. Pls referr ${env.BUILD_URL} for more info. You also can download the Error logs from the same URL." )
        
		sh 'p4 -u bangbuild -P ${P4PASSWD} -c $P4CLIENT revert //...'
		sh 'rm -rf ${WPath}/* ${LOGSERR};p4 -u bangbuild -P ${P4PASSWD} client -d $P4CLIENT'
		
		
		build job: 'Pre-iSubmit CL Rejection', parameters: [string(name: 'Changelist', value: "${ChangeList}"), string(name: 'Reason', value: 'COMPILATION_FAILED')], wait: false
		build job: 'UpdateBoxState', parameters: [string(name: 'BuildBox', value: "${Host}"), string(name: 'InUsed', value: 'NO')], wait: false
		
		currentBuild.description = "CLs : ${ChangeList}"
		sh 'exit 1'
        
    }
    
    
    stage ('CopyArtifacts') {
		def version = readFile "${WPath}/${Branch}/src_ne/latest.txt"
        if (env.Host ==~ /sv-.*/) {
			sh 'ssh bangbuild@sv-mvbld-10 "mkdir -p /bld_home/pub/osubmit_builds/${Host}/${BUILD_NUMBER}/tar_ne"'
			sh 'scp -r ${WPath}/${Branch}/tar_ne/SIM bangbuild@sv-mvbld-10:/bld_home/pub/osubmit_builds/${Host}/${BUILD_NUMBER}/tar_ne/SIM'
			build job: 'Pre-iSubmit CSIM sanity', parameters: [string(name: 'FtpLocation', value: "/bld_home/pub/osubmit_builds/${Host}/${BUILD_NUMBER}/tar_ne/${version}"), string(name: 'Changes', value: "${ChangeList}"), string(name: 'buildno', value: "${version}")], wait: false
        }
        if (env.Host ==~ /IN-.*/ || env.Host ==~ /in-.*/) { 
            build job: 'UpdateCL', parameters: [string(name: 'CLs', value: "${ChangeList}"), string(name: 'State', value: 'NEW')], wait: false
        }
    }   
    
    stage ('CleanUp WS') {
		sh 'p4 -u bangbuild -P ${P4PASSWD} -c $P4CLIENT revert //...'
		sh 'rm -rf ${WPath}/* ${LOGSERR};p4 -u bangbuild -P ${P4PASSWD} client -d $P4CLIENT'
		
		sh 'find ${LOGS} -mtime +2 | xargs rm -rf'
		build job: 'UpdateBoxState', parameters: [string(name: 'BuildBox', value: "${Host}"), string(name: 'InUsed', value: 'NO')], wait: false

    }
    }
	currentBuild.description = "CLs : ${ChangeList}"
}

