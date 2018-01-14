import jenkins
import sys
server_address = "http://sw-jenkins-m.transmode.se"

server = jenkins.Jenkins(server_address)

jobinfo = server.get_job_info(sys.argv[1])
if "anime" in jobinfo['color']:
    print("Build in progress")
    exit(1)
elif jobinfo['inQueue']:
    print("Build in queue")
    exit(1)
else:
    print("Job is idle")
    exit(0)

