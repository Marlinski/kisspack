#!/usr/bin/perl

use strict;
use warnings;
use Try::Tiny;
use XML::Parser;

my $BUILD="build";
my $ARTIFACT="artifact";

my $num_args = $#ARGV + 1;
if ($num_args < 3) {
    print "\nUsage: build_artifact.pl <git repository> <groupId> <commit> [artifact]\n";
    exit 1;
}

my $argrepo;
my $arggroupid;
my $argcommit;
my $argartifact;

if(!defined $ARGV[0]){
    print "no repo specified!\n";
    exit 1;
} else {
    $argrepo=$ARGV[0];
}

if(!defined $ARGV[1]){
    print "no group id specified!\n";
    exit 1;
} else {
    $arggroupid=$ARGV[1];
}

if(!defined $ARGV[2]){
    print "no version specified!\n";
    exit 1;
} else {
    $argcommit=$ARGV[2];
}

if(defined $ARGV[3]){
    $argartifact=$ARGV[3];
}

my $logfile = "";
my $logfh;

my $reporegexp = '((git|ssh|http(s)?)|(git@[\w\.]+))(:(//)?)([\w\.@\:/\-~]+)(\.git)(/)?';
if($argrepo =~ m/$reporegexp/) {
    my $remote = $1;
    my $projectpath = $7;

    $remote =~ s#^\/(.*$)#$1#;
    $remote =~ s#^\/(.*$)#$1#;
    $projectpath =~ s#^(.*?)\/$#$1#;
    $projectpath =~ s#^(.*?)\/$#$1#;
    
    $remote =~ s/git@([\w\.]+)/$1/;
    $remote =~ s/\./\//g;
    
    my ($projectdir, $builddir);
    try {
        ($projectdir, $builddir) = prep($remote, $projectpath, $arggroupid, $argcommit);
        $builddir = cloning($argrepo, $builddir, $argartifact);
        checkout($builddir, $argcommit);
        replacegradlew($builddir); 
        checktaskinstall($builddir, $arggroupid, $projectpath); 
        runinstall($builddir, $arggroupid, $argcommit);
        extractartifacts($builddir, $projectdir, $argcommit);
    } 
    catch {
        logfile("[!] an error occured: $_");
        cleanup($builddir);
    }
    finally {
        cleanup($builddir);
    };

    logfile("\n>>> [+] done.");
    
    if(defined $logfh) {
        close($logfh);
    }
    exit 0;
} else {
    print "[!] not a git repo";
    exit 1;
}

sub prep {
    my ($remote, $project, $groupid, $commit, $artifact) = @_;
    
    my $projectdir = "$ARTIFACT/$groupid";    
    $projectdir =~ s/\./\//g;
    $logfile  = "$projectdir/build-$commit.log";    
    die "$logfile built already performed" if ( -e $logfile );
    execute("mkdir -p $projectdir");
    open ($logfh, '>', $logfile) or die "Could not open file $logfile: $!";
   
    my $name = ( split '/', $project )[ -1 ];
    my $builddir = "$BUILD/$groupid/$commit/$name";    
    $builddir =~ s/\./\//g;
    execute("rm -rf $builddir");
    execute("mkdir -p $builddir");

    my $startmsg = "Build starting...\n";
    $startmsg = $startmsg . "start: ".localtime."\n";
    $startmsg = $startmsg . "remote=$remote\n";
    $startmsg = $startmsg . "project=$project\n";
    $startmsg = $startmsg . "version=$commit\n";
    $startmsg = $startmsg . "group=$groupid\n";
    $startmsg = $startmsg . "trigger=$artifact\n";
    logfile($startmsg);

    return ($projectdir, $builddir);
}


sub cloning {
    my ($repo, $builddir, $artifact) = @_;
    logfile("\n>>> [+] cloning $repo... ");
    execute("git clone $repo $builddir");
    if($?) {
        if(!defined $artifact) {
            die("unable to clone $repo");
        } else {
            return cloningjitpackformat($repo, $builddir, $artifact);
        }
    }
    return $builddir;
}

sub cloningjitpackformat {
    my ($repo, $builddir, $artifact) = @_;
    $repo =~ s/\.git//;
    logfile("\n>>> [+] cloning $repo/$artifact.git using jitpack format... ");
    execute("mkdir -p $builddir/$artifact");
    execute("git clone $repo/$artifact.git $builddir/$artifact");
    if($?) {
        die("unable to clone $repo, jitpack format also failed");
    }
    return "$builddir/$artifact";
}

sub checkout {
    my ($builddir, $commit) = @_;
    logfile("\n>>> [+] checking out commit $commit ... ");
    execute("cd $builddir && git checkout $commit", 1);
    die("unable to checkout commit $commit!") if $?;
}

sub replacegradlew {
    my ($builddir) = @_;
    logfile("\n>>> [+] replacing gradlew ... ");
    execute("rm $builddir/gradlew");
    execute("rm -rf $builddir/gradle");
    execute("cp -r utility/gradlew/* $builddir/");
}

sub checktaskinstall {
    my ($builddir, $group, $project) = @_;
    logfile("\n>>> [+] Looking for libraries ...");
    my $findbuildgradlecmd  = "find $builddir -name 'build.gradle' -type f \;";
    my $findbuildgradleret = `$findbuildgradlecmd`;
    my @listofbuildgradle = split /^/m, $findbuildgradleret;
    
    while(my $buildgradle=shift(@listofbuildgradle)) {
        if(haspattern($buildgradle, "java-library")) { 
            logfile("[.] found java-library: $buildgradle");
            checkjavalibrarymaven($buildgradle);
            setgroupartifact($buildgradle, $group);
        }
        if(haspattern($buildgradle, "android-library") || haspattern($buildgradle, "com.android.library")) { 
            logfile("[.] found android-library: $buildgradle");
            checkandroidlibrarymaven($buildgradle);
            setgroupartifact($buildgradle, $group);
        }
    }
}

sub checkjavalibrarymaven {
    my ($buildgradle) = @_;
    if(!haspattern($buildgradle, "'id.*?maven|plugin.*maven'")) {
        logfile("  [.] adding plugin maven to: $buildgradle");
        execute("echo '\n\napply plugin: \"maven\"' >> $buildgradle", 1);
    }
}

sub checkandroidlibrarymaven {
    my ($buildgradle) = @_;
    if(!haspattern($buildgradle, "'id.*?maven|plugin.*maven'")) {
        logfile("  [.] adding plugin android-maven to: $buildgradle");
        execute("sed -i '1s/^/plugins { id \"com.github.dcendents.android-maven\" version \"2.1\" }\\n/' $buildgradle", 1);
    }
}

sub setgroupartifact {
    my ($buildgradle, $group) = @_;
    if(!haspattern($buildgradle, "group\\s*=\\s*}")) {
        logfile("  [.] modifying artifact group in gradle: group='$group'");
        execute("sed -i 's/^\\s*group\\s*=\\s*.*\$/group=\"$group\"/' $buildgradle", 1);
    } else {
        logfile("  [.] add artifact group in gradle: group='$group'");
        execute("echo '\ngroup=\"$group\"' >> $buildgradle", 1);
    }
}

sub runinstall {
    my ($builddir, $group, $commit) = @_;
    logfile("\n>>> [+] Running install gradle task");
    execute("cd $builddir && ./gradlew clean -Pgroup=$group -Pversion=$commit -xtest install");
}

sub extractartifacts {
    my ($builddir, $projectdir, $commit) = @_;
    logfile("\n>>> [+] Looking for artifacts in build folders...");
    my $findbuildcmd  = "find $builddir -name 'build' -type d";
    my $findbuildret = `$findbuildcmd`;
    my @listofbuildfolder = split /^/m, $findbuildret;

    while(my $buildfolder=shift(@listofbuildfolder)) {
        chomp($buildfolder);
        searchpom($buildfolder, $projectdir);
    }
}

sub searchpom {
    my ($buildfolder, $projectdir) = @_;

    my $findpomcmd = "find $buildfolder -name 'pom*' -type f";
    my $findpomret = `$findpomcmd`;
    my @listofpoms = split /^/m, $findpomret;

    while(my $pompath=shift(@listofpoms)) {
        chomp($pompath);
        buildartifact($projectdir, $buildfolder, $pompath);
    }
}

sub buildartifact {
    my ($projectdir, $buildfolder, $pompath) = @_;
    my $pomartifactid  = `cat $pompath|sed -ne '/artifactId/{s/.*<artifactId>\\(.*\\)<\\/artifactId>.*/\\1/p;q;}'`;
    my $pompackaging   = `cat $pompath|sed -ne '/packaging/{s/.*<packaging>\\(.*\\)<\\/packaging>.*/\\1/p;q;}'`;
    chomp($pomartifactid);
    chomp($pompackaging);

    my $reponame = ( split '/', $projectdir )[ -1 ];
    my $artifactsubdir = $projectdir.'/'.$pomartifactid.'/'.$argcommit;
    execute("mkdir -p $artifactsubdir", 1);
    
    my $jarfile = "";
    my $jarname = "";
    if($pompackaging eq "aar") {
        my $findbuildcmd = "find $buildfolder -name '$pomartifactid*aar' -type f -print -quit";
        my $findbuildret = `$findbuildcmd`;
        chomp($findbuildret);
        if($? == 0) {
            $jarfile = "$findbuildret";
            $jarname = "$pomartifactid-$argcommit.aar";
        }
    } else {
        my $findbuildcmd = "find $buildfolder -name '$pomartifactid*jar' -type f -print -quit";
        my $findbuildret = `$findbuildcmd`;
        chomp($findbuildret);
        if($? == 0) {
            $jarfile = "$findbuildret";
            $jarname = "$pomartifactid-$argcommit.jar";
        }
    }

    if($jarfile ne "") {
        logfile("\n>>> [+] build artifact: $jarname");
        execute("cp $jarfile $artifactsubdir/$jarname", 1);
        execute("md5sum $jarfile > $artifactsubdir/$jarname.md5", 1);
        execute("sha1sum $jarfile > $artifactsubdir/$jarname.sha1", 1);
        execute("cp $pompath $artifactsubdir/$pomartifactid-$argcommit.pom", 1);
        execute("md5sum $pompath > $artifactsubdir/$pomartifactid-$argcommit.pom.md5", 1);
        execute("sha1sum $pompath > $artifactsubdir/$pomartifactid-$argcommit.pom.sha1", 1);
        $artifactsubdir =~ s/^artifact(.*)$/$1/;
        logfile("$artifactsubdir/$jarname");
        logfile("$artifactsubdir/$jarname.md5");
        logfile("$artifactsubdir/$jarname.sha1");
        logfile("$artifactsubdir/$pomartifactid-$argcommit.pom");
        logfile("$artifactsubdir/$pomartifactid-$argcommit.pom.md5");
        logfile("$artifactsubdir/$pomartifactid-$argcommit.pom.sha1\n");

    }
}

sub cleanup {
    my ($buildfolder) = @_;
    `rm -rf $buildfolder`;
}

sub execute {
    my ($ex, $silent) = @_;
    $silent = defined($silent)?$silent:0;
    if($silent == 0) {
        logfile("executing: $ex");
    }

    my $execlog = `$ex 2>&1`;
    my $ret = $?;

    if($silent == 0) {
        logfile("$execlog");
    }
    return $ret;
}

sub logfile {
    my ($debug, $silent) = @_;
    chomp($debug);
    if($debug ne "") {
        print "$debug\n";
        if(defined $logfh) {
            print $logfh "$debug\n";
        }
    }
}

sub haspattern {
    my ($file, $pattern) = @_;
    my $output = `grep -Eo $pattern $file`;
    return $? == 0;
}
