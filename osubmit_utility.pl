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
my $referenceDiskSpace = 80;
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
   'field=s' => \$dbfield,
   'set=s' => \$dbfieldvalue,
   'conditionExpr=s' => \$conditionExpr,
   'conditionValue=s' => \$conditionValue,
   'setclstate' => \$setclstate,
   'changelist=i' => \$refcl,
   'state=s' => \$refstate,
   'getClOwner' => \$getClOwner,
   'p4cl=i' => \$p4cl
  ) or die "Invalid options passed to $0\n";

die "$0 requires valid commandline user input!!! \n" unless $allocBm or $clfetch or $updateDb or $lockAction or $setclstate or $getClOwner;

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
        my @changelists;
	my @branches;
	my $isDev;
        my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
	my $query = $dbh->prepare("SELECT Shelved_Change_No,Dependent_changes FROM sanity_check.fresh_entries where Integration_Status='READY' and Branch='//swdepot/main/' order by idFresh_Entries limit 1");
        $query->execute() or die $DBI::errstr;
        my @row = $query->fetchrow_array;
        $query->finish();
        foreach (@row)
        {
            if (not defined($_) or ($_ eq "")){
                next;
            }
            else
            {
                push @changelists,$_;
		$query = $dbh->prepare("SELECT Branch FROM sanity_check.fresh_entries where Shelved_Change_No='$_'");
		$query->execute() or die $DBI::errstr;
		my $br = $query->fetchrow_array;
		$query->finish();		
		my $osubmitflagQuery = $dbh->prepare("SELECT oSubmit_flag FROM sanity_check.allowed_branch where branch='$br'");
		$osubmitflagQuery->execute() or die $DBI::errstr;
                my $flag = $osubmitflagQuery->fetchrow_array;
		$osubmitflagQuery->finish();
		$flag="true";
		if ($flag eq "true")
		{
			$clBranchMap{$_}=$br;
		}
		else {
			next;
		}

            }
        }
	$dbh->disconnect or warn "Disconnection failed: $DBI::errstr\n";
	my @osubmitInput;
	foreach my $key ( keys %clBranchMap)
	{
		#print "For changelist $key branch is $clBranchMap{$key}\n";
		my $refdepotpath=$clBranchMap{$key};
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
				
		my $pattern=$key.':'.$clBranchMap{$key}.':'.$branchType;
		#print "Pattern is $pattern\n";
		push @osubmitInput,$pattern;
	}		

        my $output=join ',', @osubmitInput;
	#print "@osubmitInput\n";
        if ($output ne "")
        {
            print "$output";
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








