env.Host="${JOB_NAME}"
env.P4CLIENT="CLV_${Branch}_${Host}"
env.CCMAIL="svarshney@infinera.com,mkrishan@infinera.com,DUpadhaye@infinera.com,jili@infinera.com,mkrishna@infinera.com"

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
	}

	
	
    try {
    stage ('Preparation')
    {
        sh 'sh get_p4_ws.sh ${Branch}'
        sh 'if [ -d ${LOGSERR} ]; then rm -rf ${LOGSERR}; fi'
        sh 'if [ ! -d ${LOGS} ]; then mkdir -p ${LOGS};fi;'
        sh 'if [ "$IsDev" == "Yes" ]; then DepotPath="//swdepot/dev/${Branch}"; else DepotPath="//swdepot/${Branch}"; fi && \
            echo "Synching Branch"; \
			p4 -u bangbuild -P ${P4PASSWD} -c ${P4CLIENT} sync $DepotPath/etc2.0/... > ${LOGS}/IQNOS_Sync.log 2>&1'
		echo "INFO : P4CLIENT -  ${P4CLIENT}"
		echo "INFO : LOGS - ${LOGS}"
		echo "INFO : LOGSERR - ${LOGSERR}"
    }
    
    stage ('Synching WA') 
    {
		parallel (
		"IQNOS" : {
		sh 'if [ "$IsDev" == "Yes" ]; then DepotPath="//swdepot/dev/${Branch}"; else DepotPath="//swdepot/${Branch}"; fi && \
            echo "Synching Branch"; \
			p4 -u bangbuild -P ${P4PASSWD} -c ${P4CLIENT} sync $DepotPath/... >> ${LOGS}/IQNOS_Sync.log 2>&1'
		},
		"2dParty": {
		sh 'echo "Synching 2dParty"; \
		    cd ${WPath}/${Branch}/etc2.0 && alias p4="p4 -u bangbuild -P ${P4PASSWD}" && ./BuildManage.sh -s > ${LOGS}/2dParty.log 2>&1'
		sh 'if [ "${Branch}" ==  "main" ]; then p4 -u bangbuild -P ${P4PASSWD} -c ${P4CLIENT}  sync //swdepot/3dParty/NM/... > ${LOGS}/3dParty.log 2>&1 ;fi'
        }
		)
    }
    
	try {
		stage('UnShelving') {
			echo "All CL to unshelve"
			sh 'CLs=`echo "${ChangeList}" | tr "," " "`; for cl in $CLs; do p4 -u bangbuild -P ${P4PASSWD} unshelve -s $cl; done'
			sh 'p4 -u bangbuild -P ${P4PASSWD} update && p4 -u bangbuild -P ${P4PASSWD} resolve -am'
			sh 'clist=`p4 -u bangbuild -P ${P4PASSWD} resolve -n | wc -l`; if [ $clist -gt 0 ]; then exit 1; fi'
			sh 'p4 -u bangbuild -P ${P4PASSWD} opened'
    
		} 
	} catch (Exception e) {
	    mail (to: "${mailer}",    
			cc: "${CCMAIL}",
			subject: "pre-iSubmit : Change# ${ChangeList} is rejected due code conflict.",
			body: "Your Changelists ${ChangeList} got rejected due to code conflict. Pls referr ${env.BUILD_URL} for more info. You have to re-submit your change after resolving the conflicts" )
		currentBuild.description = "CLs : ${ChangeList}"
		sh 'p4 -u bangbuild -P ${P4PASSWD} -c $P4CLIENT revert //...'
		sh 'rm -rf ${WPath}/* ${LOGSERR};p4 -u bangbuild -P ${P4PASSWD} client -d $P4CLIENT'
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
      stage('Compilation') {
        
        build job: 'UpdateCL', parameters: [string(name: 'CLs', value: "${ChangeList}"), string(name: 'State', value: 'INCOMPILATION')], wait: false
        
        sh 'cd ${WPath}/${Branch}/etc2.0 && HOSTNAME=$Host ./BuildManage.sh -b ALL > ${LOGS}/BuildLog.txt 2>&1'
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
		
		
		build job: 'UpdateCL', parameters: [string(name: 'CLs', value: "${ChangeList}"), string(name: 'State', value: 'COMPILATION_FAILED')], wait: false
        build job: 'UpdateBoxState', parameters: [string(name: 'BuildBox', value: "${Host}"), string(name: 'InUsed', value: 'NO')], wait: false
		
		currentBuild.description = "CLs : ${ChangeList}"
		sh 'exit 1'
        
    }
    
    
    stage ('Sanity') {
        //build job: 'UpdateCL', parameters: [string(name: 'CLs', value: "${ChangeList}"), string(name: 'State', value: 'INSANITY')], wait: false
        
        echo: "Yet to Integrate"
    
        //sh 'for cl in `echo ${ChangeList} | tr "," " "`; do perl  osubmit_utility.pl --setclstate -changelist ${cl} --state INSANITY_FAILED'
    }   
    
    stage ('CleanUp WS') {
		sh 'p4 -u bangbuild -P ${P4PASSWD} -c $P4CLIENT revert //...'
		sh 'rm -rf ${WPath}/* ${LOGSERR};p4 -u bangbuild -P ${P4PASSWD} client -d $P4CLIENT'
		
		sh 'find ${LOGS} -mtime +2 | xargs rm -rf'
		
		build job: 'UpdateBoxState', parameters: [string(name: 'BuildBox', value: "${Host}"), string(name: 'InUsed', value: 'NO')], wait: false
        build job: 'UpdateCL', parameters: [string(name: 'CLs', value: "${ChangeList}"), string(name: 'State', value: 'NEW')], wait: false
    }
    }
	currentBuild.description = "CLs : ${ChangeList}"
}

