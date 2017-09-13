#!/usr/bin/env python
#/***********************************************************************/
# *                           Copyright 2015                          
# *                             Infinera Inc.,                          
# *                        All Rights Reserved                          
# *                  Unpublished and confidential material               
# *                  --- Do not Reproduce or Disclose ---              
# *               Do not use without a written permission of            
# *                             Infinera Inc.,                                
#/***********************************************************************/
# * description        :   This file consists of class for accessing the 
# *                        infinera device thru SSH                                      
# * author             :   Govindhi Venkatachalapathy
# * email              :   gvenkatachal@infinera.com
#/***********************************************************************/
from optparse import OptionParser
import paramiko
import select
import time
import re
import sys

class InfnSSH(object):
    '''
        The InfnSSH class is the low-level class used to perform operations on the device thru ssh.
        
    '''
    def __init__(self,ip,port=22,user='infinera',passwd='Infinera.1'):
        self.ip    = ip
        self.ssh   = None
        self.shell = None
        try:
            #paramiko.common.logging.basicConfig(level=paramiko.common.DEBUG)
            self.ssh = paramiko.SSHClient()
            self.ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            self.ssh.connect(self.ip,port=port,username=user,password=passwd,timeout=30)            
            print "Connected successfully to '%s' via SSH" %self.ip
        except Exception,e:
            raise Exception("SSH connection to '%s' failed:%s" %(self.ip,str(e)))    
        return

    def sendcmd(self,cmd):
        '''
            A function which executes the command provided and verifies the string provided in the command output. Also
            if a verifystr is provided, the function would check whether the verifystr is present in the output and give
            the result as True/False depending on the match. The function also returns the output of the command.

            .. Note:: This API is not for sending the CLI commands. For executing CLI commands, please use the API *sendCliCommand()*
            
            Usage::

            >>>n = NE('10.100.210.34','root','infinera')
            >>>n.sendcommand('time')
            
        '''
        commandExecution = False
        cmd_output       = ''
        
        channel    = self.ssh.get_transport().open_session()
        channel.exec_command(cmd)
        while True:
            if channel.exit_status_ready():
                break
            rl, wl, xl = select.select([channel], [], [], 2)
            if len(rl) > 0:
                cmd_output += channel.recv(1024)
        print cmd_output
        return cmd_output


def checkforAvailableSetup(serverObj):
    '''
    '''
    total_setups = ['1','2','3','4']
    available_setups = []
    output = serverObj.sendcmd('docker ps --format "{{.Names}}"')
    running_container_names = output.split('\n')
    print running_container_names
    #Find the setup which is in use
    running_setups = []
    for rcntr in running_container_names:
        if rcntr:
            m=re.search('Pre-iSubmit_Setup(\d+)',rcntr)
            if m:
                inuse = m.group(1)
                running_setups.append(inuse)
    running_setups = list(set(running_setups))
    print '==== Setups in use are %s====' %running_setups
    
    if running_setups:
        available_setups = list(set(total_setups)-set(running_setups))
        print "===Available Setups are %s===" %available_setups
    else:
        available_setups = total_setups
        print "===Available Setups are %s===" %available_setups
        
    return available_setups
        
    

def startDockerSanity(options):
    '''
    '''
    result = True
    max_sanity_time  = 3600 # 1hr
    preisubmittests = [ 'Pre-iSubmit_Setup%s_XTC10_CSIM','Pre-iSubmit_Setup%s_XTC2_CSIM','Pre-iSubmit_Setup%s_XT500_CSIM',\
                        'Pre-iSubmit_Setup%s_XT3600_CSIM','Pre-iSubmit_Setup%s_XT3300_CSIM']
    
    
    setup_undertest = '1'
    
    #Get the running container names
    serverObj = InfnSSH('10.100.204.107')
    maxattempt     = 6
    currentattempt = 1

    while currentattempt <= maxattempt:
        available_setups = checkforAvailableSetup(serverObj)
        if available_setups:
            #Pick the first available one
            setup_undertest = available_setups[0]
            break
        #Otherwise if there is no setup available,wait for 5 mins and try again
        time.sleep(300)
        currentattempt += 1

    print "Selected setup %s for test" %setup_undertest        
    
    current_setup   = []
    #Chose the first setup from available_setups and schedule a test
    for eachtest in preisubmittests:
        setup_name = eachtest %setup_undertest
        current_setup.append(setup_name)
        cntrname   = '%s_%s' %(setup_name,options.changelists)        
        run_cmd    = 'docker run --net host -d -v /home/infinera/utah-worker/:/home/infinera/utah-worker/ \
                      -v /etc/localtime:/etc/localtime:ro --name %s  10.100.204.107:5000/infnsanity -s %s -b %s -c %s -r %s -l %s -v %s -u %s -p %s -e %s' \
                      %(cntrname,setup_name,options.build_type,options.changelists,options.release,options.buildpath,options.ftpsvr,options.ftpuser,\
                        options.ftppass,options.email)
        print run_cmd
        #Execute the docker run command
        serverObj.sendcmd(run_cmd)
        #Wait for 25 seconds before next docker
        time.sleep(25)
        
    output = serverObj.sendcmd('docker ps --format "{{.Names}}"')
    running_container_names = output.split('\n')
    if 'Setup%s' %setup_undertest in running_container_names:
        print "The Sanity has started running in Setup%s" %setup_undertest

    #Check for the results of the scheduled test
    ctime = 0
    testresultsdict = {}
    while ctime <= max_sanity_time:
        #Check whether the tests are completed.
        for es in current_setup:
            verdict = 'FAIL'
            cntrname   = '%s_%s' %(es,options.changelists)
            result_filename = '%s.txt' %cntrname
            dockerrunningcmd = "docker inspect -f '{{.State.Running}}' %s" %cntrname
            dockerrunning = serverObj.sendcmd(dockerrunningcmd).strip()
            #print "(%s)" %dockerrunning
            if 'true' in dockerrunning:
                print "docker %s still running" %cntrname
                continue
            elif 'false' in dockerrunning:
                print "docker %s completed" %cntrname
                #Check the exit code                
                eccmd = "docker inspect -f '{{.State.ExitCode}}' %s" %cntrname
                ec    = serverObj.sendcmd(eccmd).strip()
                #print "((%s))" %ec                
                if '0' in ec:
                    verdict = 'PASS'
                if not es in testresultsdict:                  
                    testresultsdict[es] = verdict
                with open(result_filename,'w') as rwr:
                    rwr.write(verdict)
        #Check for the docker status every 5 mins
        ctime += 300
        time.sleep(300)
        #print testresultsdict
        #Got all test results, hence breakout
        #print len(testresultsdict.keys())
        if len(testresultsdict.keys()) == 5:
            break
        
    print testresultsdict

    for tr in testresultsdict:
        if testresultsdict[tr] == 'FAIL':
            result = False
            
    if result and len(testresultsdict.keys()) == 5:
        print "All tests have Passed"
        sys.exit(0)
    else:
        print "One or more tests had failed or timedout ie taking more than 1hr"
        sys.exit(1)        

    
if __name__ == '__main__':
    usage = "usage: %prog [options]"
   
    parser = OptionParser(usage=usage)

    #Add the options to the tool
    parser.add_option("-c", "--changelists", dest="changelists",
                      help="ChangeLists")
    parser.add_option("-b", "--buildtype", dest="build_type",
                      help="Build Type. It can be Standard or Private. If Standard, it shall use the latest build of the current branch")
    parser.add_option("-r", "--release", dest="release",
                      help="Release. Currently only M12.0.0 is supported")     
    parser.add_option("-l", "--buildpath", dest="buildpath",
                      help="Build Path.If the build type is Private, then the user has to be specify his/her own build.", metavar="FILE")    
    parser.add_option("-v", "--ftpsvr", dest="ftpsvr",
                      help="FTP Server IP address where the build is located")
    parser.add_option("-u", "--ftpuser", dest="ftpuser",
                      help="FTP Server Username where the build is located")
    parser.add_option("-p", "--ftppass", dest="ftppass",
                      help="FTP Server Password where the build is located")
    parser.add_option("-e", "--email", dest="email",
                      help="Email receipients")       
    (options, args) = parser.parse_args()
    startDockerSanity(options)    
      
