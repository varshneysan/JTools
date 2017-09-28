import sys
import os
import re
from pymongo import MongoClient
from subprocess import *
import urllib2
from bs4 import BeautifulSoup
from pprint import pprint
from optparse import OptionParser
import traceback
import smtplib
from email.MIMEMultipart import MIMEMultipart
from email.MIMEBase import MIMEBase
from email.MIMEText import MIMEText
from email.Utils import COMMASPACE, formatdate
from email import Encoders
import socket

def getOpenISubmitDTInHtml():
    '''
        This function is used to get the Open DT issues (using Web query) and the details are then presented in a html table
    '''
    url = 'http://sv-devtrk-prd1/scripts/texcel/devtrack/report.dll?export?C3818'

    response = urllib2.urlopen(url)
    htmldata = response.read()
    response.close()  # best practice to close the file
    #Parse for the DT's in the result html file
    soup = BeautifulSoup(htmldata,'html.parser')
    itemno = 0
    dtdict = {}
    tables = soup.find_all('table')
    for table in tables:
        trs = table.find_all('tr')
        for tr in trs:
            tds = tr.find_all('td',{'align': 'left','rowspan':'1','valign': 'top'})
            if tds:
                itemno += 1
                dtdict[itemno] = {}
                dtdict[itemno]['DTId']        = re.search("<td (.+?)>\n(.+?)</td>",str(tds[0])).group(2)
                dtdict[itemno]['DTTitle']     = re.search("<td (.+?)>\n(.+?)</td>",str(tds[1])).group(2)
                dtdict[itemno]['DTSubmitter'] = re.search("<td (.+?)>\n(.+?)</td>",str(tds[2])).group(2)
                dtdict[itemno]['DTOwner']     = re.search("<td (.+?)>\n(.+?)</td>",str(tds[3])).group(2)
                dtdict[itemno]['DTStatus']    = re.search("<td (.+?)>\n(.+?)</td>",str(tds[4])).group(2)
    #print dtdict
    #Now get those DT's as a html table
    HTML_DT_HEADER = '''<br><b><u>Open oSubmit DT</b></u><br><br>'''
    HTML_DT_TABLE_HEADER = '''
    <table border="1">
       <tr bgcolor=#DBE5F1>
         <th>S No</th>
         <th>DT No</th>
         <th>DT Description</th>
         <th>Current Owner</th>
         <th>Status</th>
       </tr>
    '''
    HTML_DT_DETAILS = ''
    HTML_DT_TABLE_FOOTER = '</table><br><br>'

    dtlink = 'http://sv-devtrk-prd1/scripts/texcel/devtrack/DevTrack.dll?ViewTask?pid=12&tid=%s'
    for eachdt in dtdict:
        HTML_DT_DETAILS += '''
                <tr bgcolor=#FFFFFF>
                <td align="center">%s</td>
                <td align="center"><a href="%s">%s</a></td>                
                <td align="center">%s</td>
                <td align="center">%s</td>
                <td align="center">%s</td>
                </tr>
                ''' %(eachdt,dtlink%dtdict[eachdt]['DTId'],dtdict[eachdt]['DTId'],dtdict[eachdt]['DTTitle'],dtdict[eachdt]['DTOwner'],dtdict[eachdt]['DTStatus'])

    htmldtcontent = HTML_DT_HEADER+HTML_DT_TABLE_HEADER+HTML_DT_DETAILS+HTML_DT_TABLE_FOOTER

    #print htmldtcontent
    return htmldtcontent

def getReport():
    '''
        This function is used to query the results from the database.
    '''
    status_info = []
    client = MongoClient('mongodb://sv-utah2-dt:27017')
    db=client.testresults_database
    posts = db.posts
    tests_list = []
    querystr = {'TestName': {'$regex': '^Pre-iSubmit'},'Build': {'$regex': '%s' %options.build} }
    for post in posts.find(querystr).sort([('_id',-1)]):
        if not post['TestName'] in tests_list:
            tests_list.append(post['TestName'])       
            status_info.append(post)
    #pprint(status_info)
    return status_info

def parseHtml(fwtype,tableinfo):
    '''
    '''
    tc_count   = []
    testinfo = []
    total_tc = 0
    total_fail = 0
    trs = tableinfo.find_all('tr')
    i= 0
    for tr in trs:
        resulttd = 'FAIL'
        result = 'PASS'
        tableinfo=[]
        if i > 0:
            total_tc += 1
            tds = tr.find_all('td')
            #pprint(tds)
            try:
                resulttd = str(tds[2])
            except IndexError,e:
                if 'color:green' in tds[1]:
                    resulttd = 'PASS'
            if 'FAIL' in resulttd:
                result = 'FAIL'
                total_fail += 1
            if fwtype == 'raffle': #Raffle
                #testcasename = re.search("<td>(.+?)</td>",str(tds[6])).group(1)
                testcasename = re.search("<a (.+?)>(.+?)</a>",str(tds[1])).group(2)
            else: #Matrix
                try:
                    testcasename = re.search("<div (.+?)>(.+?)</div>",str(tds[1])).group(2)
                except:
                    testcasename = re.search('''<td align="center">(.+?)</td>''',str(tds[1])).group(1)
            tableinfo.append(testcasename)
            tableinfo.append(result)
            testinfo.append(tableinfo)
        i += 1
    total_pass = total_tc-total_fail
    tc_count = [total_tc,total_pass,total_fail]
    return testinfo,tc_count
        
        
def composeCombinedReport(row):
    '''
    '''
    totaltc        = 0
    totalpass      = 0
    totalfail      = 0
    table_to_start = 2
    url = ''
    matrix_html_file = 'test_results.html'
    byos_html_file   = 'test_report.html'
    combinedreport = {}
    testcaseinfo   = [[]]
    tccountinfo    = [0,0,0]
    
    if row['TestName'] not in combinedreport:
        combinedreport[str(row['TestName'])] = {}
    combinedreport[str(row['TestName'])]['Verdict'] = str(row['Verdict'])
    if not 'TestCaseOwners' in row:
        combinedreport[str(row['TestName'])]['TestCaseOwners'] = 'Need Owner'
    else:
        testscriptowner = ''
        if row['TestCaseOwners'] is None:
            #print row['TestName']
            #print row['TestCaseOwners']
            combinedreport[str(row['TestName'])]['TestCaseOwners'] = 'Need Owner'
        else:
            for ownerdict in row['TestCaseOwners']:
                for owner in ownerdict:
                    testscriptowner += '%s,' %owner
            if testscriptowner.endswith(','):
                testscriptowner = testscriptowner[:-1]
            combinedreport[str(row['TestName'])]['TestCaseOwners'] = testscriptowner
        
    combinedreport[str(row['TestName'])]['TestLogUrl'] = str(row['TestResultsInfo'])
    url = row['TestResultsInfo']
    #if 'Span' in row['TestName'] or 'XT500_HW' in row['TestName']:
    #     #print "I am Span/XT500 HW - %s" %row['TestName']
    #    url = "%s/%s" %(row['TestResultsInfo'],matrix_html_file)
    #    table_to_start = 3
    try:
        print url
        soup = BeautifulSoup(urllib2.urlopen(url).read(),'html5lib')
        tables = soup.find_all('table')
        table_no = 1
        for t in tables:            
            if table_no >= table_to_start:
                #Parse after table 3 or 2 for Matrix HTML Report
                tableinfo,tcinfo = parseHtml('matrix',t)
                totaltc = totaltc+tcinfo[0]
                totalpass = totalpass+tcinfo[1]
                totalfail = totalfail+tcinfo[2]
                testcaseinfo = testcaseinfo+tableinfo
                tccountinfo  = [totaltc,totalpass,totalfail]
            table_no += 1
        combinedreport[str(row['TestName'])]['TestInfo']=testcaseinfo
        combinedreport[str(row['TestName'])]['TestCaseCount']=tccountinfo        
    except Exception,e:
        print "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
        print e
        #details = traceback.format_exc()
        #print details
        pass
    #pprint(combinedreport)
    return combinedreport
    

def composeHtmlReport(status_info):
    '''
    '''
    verdict = 'PASSED'
    sanitysummaryreport = ''
    sanitysummarystatus = ''
    clowners = ''
    color_mapping   = {'PASS': 'green','FAIL': 'red','NOT AVAILABLE': 'black','PASS (with known issues)': 'orange'}
    testsummaryinfo = {}
    summarylist     = []
    csimlist = []
    hwlist   = []
    failed_tc = []
 
    #Find the hostname
    hostname = socket.gethostname()
    print hostname
    #feedbacklink = 'http://%s:8080/' %hostname+'job/iSubmit%20main%20Sanity%20feedback/parambuild/?'+'Changelists=%s' %options.changelists
    #print feedbacklink
    #HTML_HEADING = '''<BR><HTML>
    #<BODY>
    #<b><u><a href="%s">Changelists details of Pre-iSubmit Build: %s</a></b></u>
    #<BR><BR>
    #'''
    HTML_HEADING = '''<BR><HTML>
    <BODY>
    <b><u>Changelists details of Pre-iSubmit Build:%s</b></u>
    <BR><BR>
    '''
    
    HTML_FOOTER = '''
    </body></HTML>
    '''
    HTML_SUMMARY_ROW = ''

    for row in status_info:
        #if '3600' in row['TestName'] and 'test_results' in row['TestResultsInfo']:
        #    continue
        #if 'Span' in row['TestName'] or 'XT500_HW' in row['TestName']:
        rowinfo = composeCombinedReport(row)
        testsummaryinfo.update(rowinfo)
        #else:
        #    continue
    #pprint(testsummaryinfo)
    for test in sorted(testsummaryinfo):
        tempdict = {}
        tempdict[test]=testsummaryinfo[test]
        if 'hw' in test.lower():
            hwlist.append(tempdict)
        else:
            csimlist.append(tempdict)
            
          
    #pprint(csimlist)
    #pprint(hwlist)
    
    summarylist = csimlist+hwlist
    #pprint(summarylist)	

    HTML_SUMMARY_TABLE = '''
    <body>
    <b><u>Summary Report of the Sanity Test Results</b></u><br><br>
    <table border="1">
       <tr bgcolor=#DBE5F1>
         <th>S.No</th>
         <th>Test Name</th>
         <th>Test Result</th>
         <th>Total Test Cases</th>
         <th>Total Passed Test Cases</th>
         <th>Total Failed Test Cases</th>
         <th>Test Script Owner</th> 
       </tr>''' 
    HTML_SUMMARY_FOOTER = '</tr></table><br><br>'
    HTML_TC_DETAILS = ''
    totaltc = 0
    totalpass = 0
    totalfail = 0    

    sno = 1
    for tsinfo in summarylist:
        for test in tsinfo:
            bgcolor = '#E6F6FF'
            if 'hw' in test.lower():
                bgcolor = '#FFFFE6'
                
            if not 'TestCaseCount' in tsinfo[test]:
                tsinfo[test]['TestCaseCount'] = [0,0,0]                
            try:
                test_result = tsinfo[test]['Verdict']
                test_log = tsinfo[test]['TestLogUrl']
            except:
                test_log = ''
                test_result = 'NOT AVAILABLE'
            if test_result == 'FAIL':
                verdict = 'FAILED'
            
            HTML_SUMMARY_ROW +='''<tr style="color:%s" bgcolor=%s>
            <td align="center">%s</td>
            <td align="center">%s</td>
            <td align="center"><a href="%s">%s</a></td>
            <td align="center">%s</td>
            <td align="center">%s</td>
            <td align="center">%s</td>
            <td align="center">%s</td>
            </tr>
            ''' %(color_mapping[test_result],bgcolor,str(sno),test.replace('Pre-iSubmit_','').replace('_Sanity',''),test_log,test_result,tsinfo[test]['TestCaseCount'][0],\
                  tsinfo[test]['TestCaseCount'][1],tsinfo[test]['TestCaseCount'][2],tsinfo[test]['TestCaseOwners'])
            sanitysummarystatus += '%s:%s\n' %(test,test_result)
            totaltc   += tsinfo[test]['TestCaseCount'][0]
            totalpass += tsinfo[test]['TestCaseCount'][1]
            totalfail += tsinfo[test]['TestCaseCount'][2]
            sno += 1

    HTML_SUMMARY_ROW +='''
        <tr bgcolor=#FFFFFF>
        <td align="center"> </td>
        <td align="center">Total TestCases</td>
        <td align="center">%s</td>
        <td align="center">%s</td>
        <td align="center">%s</td>
        <td align="center">%s</td>
        <td align="center"></td>
        </tr>
        ''' %(verdict,totaltc,totalpass,totalfail)     

    HTML_TESTCASE_HEADER = '''<b><u>TestCase Details</b></u><br><br>'''
    HTML_TESTCASE_TABLE_HEADER = '''
    <table border="1">
       <tr bgcolor=#DBE5F1>
         <th>Test No</th>
         <th>Test Case</th>
         <th>Result</th>
         <th>Device</th>
         <th>Platform</th>
       </tr>
    '''
    HTML_TESTCASE_DETAILS = ''
    tcno = 1

    #pprint(testsummaryinfo)
    for test in testsummaryinfo:
        device   = ''
        platform = ''
        if 'Span' in test:
            device   = 'DTNX'
            platform = 'HW'
        else:
            testname = test.split('_')
            device   = testname[1]
            platform = testname[2]
            if not 'CSIM' in platform and not 'HW' in platform:
                platform = testname[3]
                device   = '%s-%s' %(testname[1],testname[2])
            
        if not 'TestInfo' in testsummaryinfo[test]:
            testsummaryinfo[test]['TestInfo'] = []
        for tc in testsummaryinfo[test]['TestInfo']:            
            try:
                #print tc
                if tc:
                    if tc[1] == 'FAIL':
                        sanitysummaryreport += '%s-%s-%s\n' %(device,platform,tc[0])
                        failed_report ='Pre-iSubmit###%s###FAIL###%s###%s' %(tc[0].strip(),device.strip(),platform.strip())
                        failed_tc.append(failed_report)

                    HTML_TESTCASE_DETAILS += '''
                    <tr bgcolor=#FFFFFF style="color:%s">
                    <td align="center">%s</td>
                    <td align="center">%s</td>
                    <td align="center">%s</td>
                    <td align="center">%s</td>
                    <td align="center">%s</td>
                    </tr>
                    ''' %(color_mapping[tc[1]],tcno,tc[0],tc[1],device,platform)
                    tcno += 1
            except IndexError,e:
                #print "Exception"
                #print e
                pass
           
    HTML_TESTCASE_FOOTER = '</table><br><br>'
    #Get the DT Issues in another new table separately
    htmldtcontent = ''
    if options.build.startswith('M17'):
        try:
            htmldtcontent = getOpenISubmitDTInHtml()
        except Exception,e:
            #Ignore if there is any exception thrown while getting the Open isubmit DT's
            pass
    
    htmlreport = HTML_HEADING %options.build+CLTABLE_HEADER+CLTABLE_ROW+CLTABLE_FOOTER+HTML_SUMMARY_TABLE+HTML_SUMMARY_ROW+HTML_SUMMARY_FOOTER+\
                 htmldtcontent+HTML_FOOTER
    #htmlreport = HTML_HEADING %(options.changelists,options.build)+HTML_SUMMARY_TABLE+HTML_SUMMARY_ROW+HTML_SUMMARY_FOOTER+\
    #             HTML_TESTCASE_HEADER+HTML_TESTCASE_TABLE_HEADER+HTML_TESTCASE_DETAILS+HTML_TESTCASE_FOOTER+\
    #             HTML_FOOTER    

    ## Save the failed test cases into known issues database if the options is provided.
    if options.ki:
        #Get the known issues from database
        kiclient = MongoClient('sv-utah2-dt',27017)
        kidb=kiclient.knowntiming_database
        kiposts = kidb.posts
        dbentry = {'KnownIssues': failed_tc}
        
        if not options.override:
            ki    = []
            for p in kiposts.find():
                ki = p['KnownIssues']
            
            alreadyin =set(failed_tc).intersection(ki)
            #pprint(failed_tc)
            #pprint(ki)
            #pprint(alreadyin)
            for issue in failed_tc:
                if issue not in alreadyin:
                    ki.append(issue)
            #pprint(ki)
            dbentry = {'KnownIssues': ki }
        
        #Put the failed tc's in the db now        
        for row in kiposts.find(): #There will be only one row anyway. Update the same
            result = kiposts.update_one({"_id": row['_id']},{"$set": dbentry})
            
    ##    #Save the HTML content in a file
    with open('test.html','w') as statuswr:
        statuswr.write(htmlreport)
    ## Save the summary table in a separate file so that it can be used as a description for automatic DB Update
    with open('%s_summary_status.txt' %options.build,'w') as verdictwr:
        verdictwr.write(sanitysummarystatus)
    with open('summary_preisubmit_sanity_%s.txt' %options.build,'w') as summarywr:
        summarywr.write(sanitysummaryreport)
    return htmlreport,verdict

def sendEmail(htmlcontent,verdict):
    '''
        This method is used send email the test execution report in html using SMTP.
    '''
    mailserver = '10.100.98.58'
    try:
        subject = "Pre-iSubmit %s: Sanity Tests %s" %(options.build,verdict)
        frm = "SWToolAdmin@infinera.com"
        to = options.email.split(',')
        msg = MIMEMultipart('alternative')
        msg['From'] = frm
        msg['To'] = COMMASPACE.join(to)
        msg['Date'] = formatdate(localtime=True)
        msg['Subject'] = subject
        msg.attach( MIMEText(htmlcontent,'html') )
        smtp = smtplib.SMTP(mailserver) 
        smtp.sendmail(frm, to, msg.as_string() )
        smtp.close()
        print "Email Sent"
    except Exception, details:
        raise Exception('Error in sending email:%s'%details)
    

if __name__ == '__main__':
    usage = "usage: %prog [options]"
   
    parser = OptionParser(usage=usage)

    #Add the options to the tool
    parser.add_option("-c", "--changelists", dest="changelists",
                      help="ChangeLists")
    parser.add_option("-b", "--build", dest="build",
                      help="Build Name.Example: M16.1.0.1077")
    parser.add_option("-e", "--email", dest="email",
                      help="Email receipients. Multiple emails are comma separated.")
    parser.add_option("-k", "--ki", dest="ki",action="store_true",default=False,
                      help="If this option is provided, the failed test cases will be stored as Known Issues in DB.In this case, the failed test cases from this build will be appended to the existing known issue if not present already")
    parser.add_option("-o", "--o", dest="override",action="store_true",default=False,
                      help="-k should be provided to use this option.If this option is provided, the already existing failed test cases will be overriden with this build failed test cases ie only this failed test cases exists in the known issues DB. The Previous entry will be deleted.")      

    (options, args) = parser.parse_args()
    #Find the email ids of the changelist owners from changelist numbers
    addemail       = ''
    owners         = ''
    
    CLTABLE_HEADER = '''
    <table border="1">
       <tr bgcolor=#DBE5F1>
         <th>Pre-iSubmit CL</th>
         <th>DT</th>
         <th>UserId</th>
         <th>Files Affected</th>
       </tr>
    '''
    CLTABLE_FOOTER = '''</table><br><br>'''
    CLTABLE_ROW = ''
    if options.changelists:
        if options.changelists.endswith(','):
            options.changelists = options.changelists[:-1] #Remove the last comma
        cls            = options.changelists.split(',')      
        i=0
        for cl in cls:
            if cl:
                filelist = ''
                dtstr = 'None'
                bcol = "#FFFFFF"
                if i%2 != 0:
                    bcol = "#E7EDF5"
                isubmitcl = ''
                submitter = ''
                dts       = []
                p = Popen(["/usr/bin/p4","-p","perforce:1666","-u","bangbuild","-P","B11FFB5FFDE3BBA9470A8318DE219A76","describe","-sO",cl],stdout=PIPE)
                output,err = p.communicate()
                #print output
                for line in output.split('\n'):
                    line=line.strip()
                    if line.startswith('... //swdepot'):
                        filelist += line+'<br>'
                        
                m=re.search('Change (\d+) by (\w+)\@',output)
                if m:
                    isubmitcl = m.group(1)
                    submitter = m.group(2)
                    owners += submitter+','
                    addemail += '%s@infinera.com,' %submitter
                #Now find if there are any DT's associated with that
                dts = re.findall('dawn(\d+) on',output)
                if dts:
                    dtstr = ','.join(dts)
                CLTABLE_ROW += '''
                <tr bgcolor=%s>
                    <td align="center">%s</td>
                    <td align="center">%s</td>
                    <td align="center">%s</td>
                    <td>%s</td>
                </tr>
                '''%(bcol,isubmitcl,dtstr,submitter,filelist)
                i+=1
    #print addemail
    #print dtstr
    options.email = addemail+options.email
    status      = getReport()
    htmlcontent,verdict = composeHtmlReport(status)
    sendEmail(htmlcontent,verdict)

