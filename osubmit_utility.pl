#!/usr/bin/perl

use List::UtilsBy qw(min_by);
use strict;
use Cwd;
use DBI;
use Getopt::Long;

my $isNetSshInstalled;
BEGIN {
    unless (eval "use Net::SSH::Perl") {
        $isNetSshInstalled="YES";
    }
}

# Database details
my $driver = "mysql";
my $database = "sanity_check";
my $osubmitdb= "osubmit";
my $dbhost = '10.220.0.33';
my $dsn = "DBI:$driver:database=$database;host=$dbhost";
my $osubmitdsn = "DBI:$driver:database=$osubmitdb;host=$dbhost";
my $userid =  unpack(chr(ord("a") + 19 + print ""),'$<F]O=```');
my $password = unpack(chr(ord("a") + 19 + print ""),'$<F]O=```');

# Server parameters
my %serverParam;
my $referenceDiskSpace = 90;
my $referenceBmProcCount = 2;

my $svpasswd = unpack(chr(ord("a") + 19 + print ""),',8G5I;&1E<D!I;F9N');
my $inpasswd = unpack(chr(ord("a") + 19 + print ""),');&YX8FQD0#@P');

my $allocBm;
my $clfetch;
my $updateDb;
my $dbschema;
my $dbtable;
my $refchangelist;
my $dbfield;
my $dbfieldvalue;
my $conditionExpr;
my $conditionValue;
my $serverToLock;
my $serverStatus;
my $lockAction;
my $setclstate;
my $refcl;
my $refstate;
my $getClOwner;
my $p4cl;
my $rejectChangelist;
my $rejectionReason;
my $sanityflag;
my $currentBranch;
my $updatetimestamp;


# Process inputs from user
GetOptions(
   'allocBuildMachine' => \$allocBm,
   'fetchChangelist' => \$clfetch,
   'lockUnLockBuildBox' => \$lockAction,
   'server=s' => \$serverToLock,
   'status=s' => \$serverStatus,
   'updateDb' => \$updateDb,
   'database=s' => \$dbschema,
   'dbtable=s' => \$dbtable,
   'conditionExpr=s' => \$conditionExpr,
   'conditionValue=s' => \$conditionValue,
   'setclstate' => \$setclstate,
   'changelist=i' => \$refcl,
   'state=s' => \$refstate,
   'getClOwner' => \$getClOwner,
   'p4cl=i' => \$p4cl,
   'rejectChangelist' => \$rejectChangelist,
   'reason=s' => \$rejectionReason,
   'isSanityEnabled' => \$sanityflag,
   'branch=s' => \$currentBranch,
   'updatetime' => \$updatetimestamp,
   'field=s' => \$dbfield,
   'set=s' => \$dbfieldvalue

  ) or die "Invalid options passed to $0\n";

die "$0 requires valid commandline user input!!! \n" unless $allocBm or $clfetch or $updateDb or $lockAction or $setclstate or $getClOwner or $rejectChangelist or $sanityflag or $updatetimestamp;

if ($allocBm and $clfetch)
{
 die "$0 requires either --allocBuildMachine or --fetchChangelist commandline user input.Both options are not permitted!!! \n";
}

if ($setclstate)
{
	&setClState($refcl,$refstate);

}

if ($allocBm)
{
    &allocBuildMachine;
    exit;
}

if ($lockAction)
{
	&lockUnLockBuildBox($serverToLock,$serverStatus);
	exit;	
}

if ($clfetch)
{
    &getNewOsubmitCandidate;
    exit;
}

if ($updateDb)
{
    die "$0 requires database, database table , field and value .\n" unless $dbschema or $dbtable or $dbfield or $dbfieldvalue;
    &updateDbField;
    exit;
}

if ($getClOwner)
{
    &getClOwner($p4cl);
    exit;
}

if ($rejectChangelist)
{
    &rejectCl($p4cl,$rejectionReason);
    exit; 
}

if ($sanityflag)
{
    &isSanityEnabled($currentBranch);
    exit;
}

if ($updatetimestamp)
{
    &update_active_time($p4cl,$dbfield);
}

sub allocBuildMachine {

    # Get servers from the pool
      my $serverlist=&getServersFromPool;
      #print "Servers available in the pool are @$serverlist\n\n";

    # Get parameters from all the servers
    #print "---------------------------------------------------------\n";
    foreach my $server (@$serverlist)
    {
        my $user =  unpack(chr(ord("a") + 19 + print ""),'$<F]O=```');
        my $passwd;
        my $homedirpattern;
        if ( $server =~ /^sv-/)
        {
        $homedirpattern="bld_home";
            #print "For server $server , we need to check space in $homedirpattern\n";
            $passwd=$svpasswd;
        }
        else
        {
            $homedirpattern="home";
            #print "For server $server , we need to check space in $homedirpattern\n";
            $passwd=$inpasswd;
        }

        my $disk_space_check_cmd = "df -hP | grep $homedirpattern | awk -F \" \" '{ print \$5 }' | sed 's/.\$//'";
        my $BM_count_cmd = "ps -ef | grep \"./BuildManage.sh\" | grep \"\\-b\"| grep \"ALL\" | cut -d\" \" -f1 |grep -v root|sort|uniq| wc -l";

        #-- set up a new connection
        my $ssh;
        eval
        {
            $ssh = Net::SSH::Perl->new($server) or die $@;
        };
        if ($@)
        {
            next;
        }
        $ssh->login($user,$passwd);
        my($stdout, $stderr, $exit) = $ssh->cmd($disk_space_check_cmd);
        my($stdoutbm, $stderrbm, $exitbm) = $ssh->cmd($BM_count_cmd);
        #print "\n*** Extracting parameters from server $server ***\n";
        #print "Disk space usage parameter % is $stdout";
        #print "Number of BuildManage process running is $stdoutbm";
        #print "---------------------------------------------------------\n";
        $serverParam{"diskspace"}{$server}=$stdout;
        $serverParam{"bmproccount"}{$server}=$stdoutbm;
    }

        #print "\n *** Server parameters are ***\n";
        foreach my $param (sort keys %serverParam) {
            my $href= $serverParam{$param};
            foreach my $key ( keys %{ $href } )
            {
                #print "Server : $key Parameter : $param  Value: ${$href}{$key}\n";
            }
        }
    while (1)
    {
        my $lowestProcCountServer = min_by { $serverParam{"bmproccount"}{$_}} keys %{$serverParam{"bmproccount"}};
        my $lowestProcCountValue = $serverParam{"bmproccount"}{$lowestProcCountServer};
        if ( $lowestProcCountValue <= $referenceBmProcCount)
        {
            my $diskUsageValue = $serverParam{"diskspace"}{$lowestProcCountServer};
            #print "Disk space usage value for server $lowestProcCountServer is $diskUsageValue \n";
            if ($diskUsageValue <= $referenceDiskSpace)
            {
                print "$lowestProcCountServer";
                last;
            }
            else
            {
                delete($serverParam{"diskspace"}{$lowestProcCountServer});
                delete($serverParam{"bmproccount"}{$lowestProcCountServer});
            }
        }
        else
        {
            print "None";
        }
    }
}


# Get servers whcih are good (oSubmit enabled) and are not is use currently
sub getServersFromPool {

my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
my $query = $dbh->prepare("SELECT server_name FROM sanity_check.known_servers where is_good='YES' and is_used='NO'");
$query->execute() or die $DBI::errstr;
#my $ary_ref = $dbh->selectcol_arrayref("SELECT server_name FROM test2.server where is_good='YES'");
my $ary_ref = $dbh->selectcol_arrayref("SELECT server_name from sanity_check.known_servers where is_good='YES' and is_used='NO'");
$query->finish();
$dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
if (not defined $ary_ref )
{
    print "None";
    exit;
}
else
{
    return $ary_ref;
}
}
# Get changelists for osubmit job

sub getNewOsubmitCandidate {
    my %clBranchMap;
    my %osubmitClRecord;
    my $isDev;
    my $shelvedChangeNo;
    my $validinput="false";
    my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
    my $query = $dbh->prepare("SELECT Shelved_Change_No FROM sanity_check.fresh_entries where Integration_Status='READY' order by idFresh_Entries");
    $query->execute() or die $DBI::errstr;
    while (my $record = $query->fetchrow_array())
    {
            $shelvedChangeNo=$record;
            my $clbranch=&getBranchForCl($shelvedChangeNo);
            my $osubmitflag=&isOsubmitEnabledBranch($clbranch);
            #print "iSubmitted changelist is $shelvedChangeNo ,p4 branch is $clbranch and oSubmit flag is $osubmitflag \n";
            if ($osubmitflag eq "true")
            {
                #print "Push CL $shelvedChangeNo to oSubmit build job \n";
                $osubmitClRecord{"isubmittedcl"}= $shelvedChangeNo;
                $clBranchMap{$shelvedChangeNo}=$clbranch;
                $validinput="true";
                last;
            }
            else {
                next;
            }
    }
    $query->finish();
    if (not defined($shelvedChangeNo) or ($shelvedChangeNo eq "")){
                print "None";
                exit;
    }
    if ( $validinput eq "false"){
         print "None";
                exit;
    }

    # we have got the CL now
    $query = $dbh->prepare("SELECT Dependent_changes,2dParty_Applicable_Branch FROM sanity_check.fresh_entries where Shelved_Change_No='$shelvedChangeNo'");
    $query->execute() or die $DBI::errstr;
    my @osubmitinputcldep = $query->fetchrow_array();
    $query->finish();
    $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
    if (not defined($osubmitinputcldep[0]) or ($osubmitinputcldep[0] eq "")){
         $osubmitClRecord{"depChanges"}="NONE";
    }
    else {
        $osubmitClRecord{"depChanges"}=$osubmitinputcldep[0];
    }
    if (not defined($osubmitinputcldep[1]) or ($osubmitinputcldep[1] eq "")){
        $osubmitClRecord{"2dpAppBranch"}="NONE";
    }
    else {
        $osubmitClRecord{"2dpAppBranch"}= $osubmitinputcldep[1];
    }

    my @osubmitInput;
    my @osubmitInputFields=("depChanges","2dpAppBranch");
    my $basebranch= &getBranchForCl($osubmitClRecord{"isubmittedcl"});
    my $basepattern=$osubmitClRecord{"isubmittedcl"}.':'.$basebranch.':'.&getBranchType($basebranch);
    #print "*** pattern is $basepattern";
    push @osubmitInput,$basepattern;

    if( $osubmitClRecord{"depChanges"} eq "NONE")
    {
        push @osubmitInput,"NONE";
    }
    else
    {
        my $cl = $osubmitClRecord{"depChanges"};
        my $br = &getBranchForCl($cl);
        my $brtype = &getBranchType($br);
        my $pattern= $cl.':'.$br.':'. $brtype;
        push @osubmitInput,$pattern;
    }

    if( $osubmitClRecord{"2dpAppBranch"} eq "NONE")
    {
        push @osubmitInput,"NONE";
    }
    else
    {
        my $brtype =  &getBranchType($osubmitClRecord{"2dpAppBranch"});
        my $none="NONE";
        my $pattern = $none.':'.$osubmitClRecord{"2dpAppBranch"}.':'.$brtype;
        push @osubmitInput, $pattern;
    }

    my $finaloutput=join ',', @osubmitInput;
    #print "@osubmitInput\n";
    if ($finaloutput ne "")
    {
        print "$finaloutput";
    }
    else
    {
       print "None";
    }
}

# Update field value for a given database table

sub updateDbField {
    my $query;
    my $temp = $dbschema.'.'.$dbtable;
    my $dsn = "DBI:$driver:database=$dbschema;host=$dbhost";
    my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
    if ($conditionExpr and $conditionValue)
    {
        $query = $dbh->prepare("UPDATE $temp SET $dbfield='$dbfieldvalue' where $conditionExpr='$conditionValue'");
    }
    else
    {
        $query = $dbh->prepare("UPDATE $temp SET $dbfield='$dbfieldvalue'");
    }
    $query->execute() or die $DBI::errstr;
    $query->finish();
    $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
}


# Lock the build box 

sub lockUnLockBuildBox {
	my $name = shift;
	my $st = shift;
	my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
	my $query = $dbh->prepare("UPDATE sanity_check.known_servers SET is_used='$st' where server_name='$name'");
	$query->execute() or die $DBI::errstr;
	$query->finish();
	$dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
}


sub setClState {

        my $cl = shift;
        my $st = shift;
        my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
        my $query = $dbh->prepare("UPDATE sanity_check.fresh_entries SET Integration_Status='$st' where Shelved_Change_No='$cl'");
        $query->execute() or die $DBI::errstr;
        $query->finish();
        $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";

}

sub getClOwner {
    my $cl = shift;
    my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
    my $query = $dbh->prepare("SELECT Developer FROM sanity_check.fresh_entries where Shelved_Change_No = '$cl'");
    $query->execute() or die $DBI::errstr;
    my $dev = $query->fetchrow_array;
    $query->finish();
    $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
    if (not defined($dev) or ($dev eq "")){
        print "None";
        exit;
    }
    else
    {
        print "$dev\@infinera\.com";
        exit;
    }
}

sub  rejectCl {

    my $cl = shift;
    my $reason = shift;
    my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
    my $query = $dbh->prepare("insert into sanity_check.osubmit_failed_history (Developer,Shelved_Change_No,Date,Feature_Bug_No,Branch,Dependent_changes,Integration_Status,Build_Status,Sanity_Status,Reviewer,Tested,TestCase,Description,local_change,Build_Number,2dParty_Applicable_Branch) select Developer,Shelved_Change_No,Date,Feature_Bug_No,Branch,Dependent_changes,Integration_Status,Build_Status,Sanity_Status,Reviewer,Tested,TestCase,Description,local_change,Build_Number,2dParty_Applicable_Branch from sanity_check.fresh_entries where Shelved_Change_No = '$cl'");
    $query->execute() or die $DBI::errstr;
    $query->finish();
    $query = $dbh->prepare("UPDATE sanity_check.osubmit_failed_history SET Build_Status='$reason' where Shelved_Change_No='$cl'");
    $query->execute() or die $DBI::errstr;
    $query->finish();
    $query = $dbh->prepare("DELETE FROM sanity_check.fresh_entries WHERE Shelved_Change_No='$cl'");
    $query->execute() or die $DBI::errstr;
    $query->finish();
    $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
}

sub  isOsubmitEnabledBranch {
        my $br = shift;
        my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
        my $osubmitflagQuery = $dbh->prepare("SELECT oSubmit_flag FROM sanity_check.allowed_branch where branch='$br'");
        $osubmitflagQuery->execute() or die $DBI::errstr;
        my $flag = $osubmitflagQuery->fetchrow_array;
        $osubmitflagQuery->finish();
        $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
        return $flag;
}

sub  getBranchForCl {
    my $cl = shift;
    my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
    my $query = $dbh->prepare("SELECT Branch FROM sanity_check.fresh_entries where Shelved_Change_No='$cl'");
    $query->execute() or die $DBI::errstr;
    my $br = $query->fetchrow_array;
    $query->finish();
    $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
    return $br;
}

sub getBranchType {
     my $refdepotpath=shift;
     my $isDevBranch;
     my $branchType;
     if (( split '/', $refdepotpath )[3] eq "dev")
     {
        $isDevBranch ="YES";
        $branchType ="DEV";
        #print "$refdepotpath is a development branch\n";
      }
    else {
        $isDevBranch ="NO";
        $branchType ="NONDEV";
        #print "$refdepotpath is NOT a development branch\n";
    }
    return $branchType;
}

sub isSanityEnabled {

    my $branch = shift;
    my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
    my $osubmitSanityflagQuery = $dbh->prepare("SELECT oSubmitSanity_flag FROM sanity_check.allowed_branch where branch like '$branch%'");
    $osubmitSanityflagQuery->execute() or die $DBI::errstr;
    my $flag = $osubmitSanityflagQuery->fetchrow_array;
    $osubmitSanityflagQuery->finish();
    $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
    if (not defined($flag) or ($flag eq "") or ($flag eq "false")){
        print "NO";
    }
    else
    {
        print "YES";
    }

}

sub update_active_time {
    my $CL = shift;
    my $field = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    $mon++;
    $year=$year + 1900;
    my $tformat="$year" . "-" . "$mon" . "-" . "$mday" . " " . "$hour" . ":" . $min . ":" . $sec;

    my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
    if ($field == "load_mgr_pickup_end_time") {
       my $osubmitSanityflagQuery = $dbh->prepare("SELECT iSubmitted_CL FROM sanity_check.tbl_preisubmit_data WHERE iSubmitted_CL='$CL'");
       $osubmitSanityflagQuery->execute() or die $DBI::errstr;
       my $flag = $osubmitSanityflagQuery->fetchrow_array;
       $osubmitSanityflagQuery->finish();
       if (not defined($flag) or ($flag eq "")) { 
 	  print "No entry for $CL\n";
          my $osubmitSanityflagQuery = $dbh->prepare("INSERT INTO sanity_check.tbl_preisubmit_data (iSubmitted_CL) VALUES ('$CL')");
	  $osubmitSanityflagQuery->execute() or die $DBI::errstr;
          $osubmitSanityflagQuery->finish();
       }
    }
    my $osubmitSanityflagQuery = $dbh->prepare("UPDATE sanity_check.tbl_preisubmit_data SET $field='$tformat' WHERE iSubmitted_CL='$CL'");
    $osubmitSanityflagQuery->execute() or die $DBI::errstr;
    $osubmitSanityflagQuery->finish();
    $dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n"; 
}

